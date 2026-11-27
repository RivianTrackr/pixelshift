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

    /// Resize jobs whose result would be saved over one of the files being read:
    /// the original itself (same folder, same name), or another dropped file
    /// (photo.png → photo.jpg when photo.jpg is in the batch too).
    public static func replacingOriginals(_ jobs: [BatchJob]) -> [BatchJob] {
        let sources = Set(jobs.map { pathKey($0.source) })
        return jobs.filter { $0.kind == .resize && sources.contains(pathKey($0.destination)) }
    }

    /// Mac volumes are usually case-insensitive, so compare paths that way.
    static func pathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
    }

    public enum Placement: Sendable, Equatable {
        /// Results go under this folder; dropped folders keep their structure.
        case folder(URL)
        /// Each result goes in the same folder as its original.
        case besideOriginals
    }

    /// Convenience for the folder placement with no name suffix.
    public static func collect(from urls: [URL], into destination: URL, format: OutputFormat, copyNonImageFiles: Bool) -> [BatchJob] {
        collect(from: urls, placement: .folder(destination), format: format, suffix: "", copyNonImageFiles: copyNonImageFiles)
    }

    /// Expands dropped files and folders into jobs. Images get the output
    /// extension and `suffix`; other files are copied as-is when
    /// `copyNonImageFiles` is on (never beside the originals, where a copy
    /// would be a pointless duplicate).
    public static func collect(from urls: [URL], placement: Placement, format: OutputFormat,
                               suffix: String, copyNonImageFiles: Bool) -> [BatchJob] {
        let fm = FileManager.default
        var jobs: [BatchJob] = []
        var claimed = Set<String>()

        func add(_ file: URL, relativeDir: String) {
            let name = file.lastPathComponent
            guard !name.hasPrefix(".") else { return }
            let isImage = isReadableImage(file)
            let beside = placement == .besideOriginals
            guard isImage || (copyNonImageFiles && !beside) else { return }

            let stem = isImage ? file.deletingPathExtension().lastPathComponent : (name as NSString).deletingPathExtension
            // Beside the originals, skip results of an earlier run (photo-1200.jpg).
            if beside && !suffix.isEmpty && stem.hasSuffix(suffix) { return }

            let ext = isImage ? format.fileExtension : (name as NSString).pathExtension
            let base = isImage ? stem + suffix : stem
            func fileName(_ n: Int?) -> String {
                let numbered = n.map { "\(base) \($0)" } ?? base
                return ext.isEmpty ? numbered : "\(numbered).\(ext)"
            }

            let folder: URL
            let shownDir: String
            switch placement {
            case .folder(let root):
                folder = relativeDir.isEmpty ? root : root.appendingPathComponent(relativeDir)
                shownDir = relativeDir
            case .besideOriginals:
                folder = file.deletingLastPathComponent()
                shownDir = folder.lastPathComponent
            }

            // Two inputs that land on one name (photo.png + photo.jpg) get a number.
            var outName = fileName(nil)
            var n = 2
            while claimed.contains(folder.appendingPathComponent(outName).path.lowercased()) {
                outName = fileName(n)
                n += 1
            }
            let destination = folder.appendingPathComponent(outName)
            claimed.insert(destination.path.lowercased())

            jobs.append(BatchJob(
                source: file,
                destination: destination,
                kind: isImage ? .resize : .copy,
                displayName: shownDir.isEmpty ? outName : "\(shownDir)/\(outName)"
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
