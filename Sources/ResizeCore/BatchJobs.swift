import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct BatchJob: Sendable, Equatable {
    public enum Kind: Sendable { case resize, copy }
    public var source: URL
    public var destination: URL
    public var kind: Kind

    /// Where the result goes relative to the chosen folder, for display.
    public var displayName: String
}

public enum BatchJobs {
    /// Types ImageIO can decode, read once.
    private static let readableTypes: [UTType] = {
        let ids = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return ids.compactMap(UTType.init)
    }()

    public static func isReadableImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return false }
        return readableTypes.contains { type.conforms(to: $0) }
    }

    /// Expands dropped files and folders into jobs. Folders keep their
    /// structure under `destination`; images get the output extension;
    /// other files are copied as-is when `copyNonImageFiles` is on.
    public static func collect(from urls: [URL], into destination: URL, format: OutputFormat, copyNonImageFiles: Bool) -> [BatchJob] {
        let fm = FileManager.default
        var jobs: [BatchJob] = []
        var claimed = Set<String>()

        func add(_ file: URL, relativeDir: String) {
            let name = file.lastPathComponent
            guard !name.hasPrefix(".") else { return }
            let isImage = isReadableImage(file)
            guard isImage || copyNonImageFiles else { return }

            let base = isImage ? file.deletingPathExtension().lastPathComponent : name
            let ext = isImage ? format.fileExtension : ""
            var outName = ext.isEmpty ? base : "\(base).\(ext)"
            var relative = relativeDir.isEmpty ? outName : "\(relativeDir)/\(outName)"

            // Two inputs that land on one name (photo.png + photo.jpg) get a suffix.
            var n = 2
            while claimed.contains(relative.lowercased()) {
                let stem = isImage ? base : (name as NSString).deletingPathExtension
                let origExt = isImage ? ext : (name as NSString).pathExtension
                outName = origExt.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(origExt)"
                relative = relativeDir.isEmpty ? outName : "\(relativeDir)/\(outName)"
                n += 1
            }
            claimed.insert(relative.lowercased())

            jobs.append(BatchJob(
                source: file,
                destination: destination.appendingPathComponent(relative),
                kind: isImage ? .resize : .copy,
                displayName: relative
            ))
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue else {
                add(url, relativeDir: "")
                continue
            }

            let root = url.lastPathComponent
            let basePath = url.standardizedFileURL.path
            guard let walker = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var files: [URL] = []
            for case let file as URL in walker {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    files.append(file)
                }
            }
            files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            for file in files {
                let parent = file.deletingLastPathComponent().standardizedFileURL.path
                var sub = parent.hasPrefix(basePath) ? String(parent.dropFirst(basePath.count)) : ""
                if sub.hasPrefix("/") { sub.removeFirst() }
                add(file, relativeDir: sub.isEmpty ? root : "\(root)/\(sub)")
            }
        }
        return jobs
    }
}
