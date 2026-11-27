import AppKit
import Observation
import ResizeCore
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

struct BatchSummary {
    var resized = 0
    var copied = 0
    var skipped = 0
    var failures: [(name: String, message: String)] = []
    var cancelled = false
    var destination: URL
    var seconds: Double = 0
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var options: ResizeOptions {
        didSet { if options != oldValue { OptionsStore.save(options) } }
    }

    // Progress
    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var total = 0
    private(set) var currentName = ""
    var summary: BatchSummary?

    var library: PresetLibrary {
        didSet { if library != oldValue { OptionsStore.save(library) } }
    }

    var presetIsModified: Bool { library.isModified(options) }

    private var runTask: Task<Void, Never>?

    private init() {
        options = OptionsStore.load()
        library = OptionsStore.loadLibrary()
    }

    // MARK: Presets

    func selectPreset(_ preset: Preset) {
        library.selectedID = preset.id
        options = options.applying(preset)
    }

    func saveAsNewPreset() {
        let suggested = library.selected.map { "\($0.name) copy" } ?? "My preset"
        guard let name = askForName(title: "Save current settings as a preset", value: suggested, button: "Save")
        else { return }
        library.add(name: name, options: options)
    }

    func updateSelectedPreset() {
        library.updateSelected(with: options)
    }

    func renameSelectedPreset() {
        guard let current = library.selected,
              let name = askForName(title: "Rename preset", value: current.name, button: "Rename")
        else { return }
        library.renameSelected(to: name)
    }

    func deleteSelectedPreset() {
        guard let current = library.selected else { return }
        let a = NSAlert()
        a.messageText = "Delete the preset “\(current.name)”?"
        a.informativeText = "Your current settings stay as they are."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        if a.runModal() == .alertFirstButtonReturn { library.deleteSelected() }
    }

    private func askForName(title: String, value: String, button: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        a.accessoryView = field
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: Entry points

    func chooseFilesAndProcess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose images or folders to resize"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return }
        process(panel.urls)
    }

    func process(_ urls: [URL]) {
        guard !isRunning, !urls.isEmpty else { return }
        NSApp.activate()

        if let problem = options.validationError {
            alert("Some resizing settings need fixing.", problem)
            return
        }

        // Reopen the watermark through its bookmark (needed in the sandbox),
        // just long enough for the resizer to load it into memory.
        let watermark = WatermarkAccess(options: options)
        if let fresh = watermark.refreshedBookmark { options.watermarkBookmark = fresh }
        var runOptions = options
        if let path = watermark.url?.path { runOptions.watermarkPath = path }

        let resizer: ImageResizer
        do {
            resizer = try ImageResizer(options: runOptions)
            watermark.stop()
        } catch {
            watermark.stop()
            alert("The watermark couldn’t be loaded.", error.localizedDescription)
            return
        }

        guard let destination = chooseDestination() else { return }
        options.lastDestination = destination.path

        var jobs = BatchJobs.collect(from: urls, into: destination, format: options.format,
                                     copyNonImageFiles: options.copyNonImageFiles)
        guard !jobs.isEmpty else {
            alert("Nothing to resize.", "None of the dropped items are images this Mac can read.")
            return
        }

        var summary = BatchSummary(destination: destination)
        guard resolveConflicts(&jobs, summary: &summary) else { return }
        run(jobs, resizer: resizer, summary: summary)
    }

    func cancel() { runTask?.cancel() }

    func confirmQuitWhileRunning() -> NSApplication.TerminateReply {
        let a = NSAlert()
        a.messageText = "Resizing is still in progress."
        a.informativeText = "Quit anyway? Files already finished are kept."
        a.addButton(withTitle: "Keep Resizing")
        a.addButton(withTitle: "Quit")
        return a.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Steps

    private func chooseDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save the resized images"
        panel.prompt = "Save Here"
        // The panel runs outside the sandbox, so it can open at the last folder
        // without this app holding access to it; the user's pick grants access.
        if let last = options.lastDestination {
            panel.directoryURL = URL(fileURLWithPath: last)
        } else {
            panel.directoryURL = URL(fileURLWithPath: realHomeDirectory()).appendingPathComponent("Downloads")
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks about files that already exist. Returns false if the user cancels.
    private func resolveConflicts(_ jobs: inout [BatchJob], summary: inout BatchSummary) -> Bool {
        let fm = FileManager.default
        var kept: [BatchJob] = []
        var applyToAll: Bool?   // true = overwrite all, false = skip all

        for job in jobs {
            // Never copy a file onto itself.
            if job.kind == .copy && job.source.standardizedFileURL == job.destination.standardizedFileURL {
                summary.skipped += 1
                continue
            }
            guard options.warnBeforeOverwriting, fm.fileExists(atPath: job.destination.path) else {
                kept.append(job)
                continue
            }
            let overwrite: Bool
            if let all = applyToAll {
                overwrite = all
            } else {
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = "“\(job.destination.lastPathComponent)” already exists."
                a.informativeText = "It is in \(job.destination.deletingLastPathComponent().path). Replace it with the resized file?"
                a.addButton(withTitle: "Replace")
                a.addButton(withTitle: "Skip")
                a.addButton(withTitle: "Cancel")
                a.showsSuppressionButton = true
                a.suppressionButton?.title = "Apply to all"
                let response = a.runModal()
                if response == .alertThirdButtonReturn { return false }
                overwrite = response == .alertFirstButtonReturn
                if a.suppressionButton?.state == .on { applyToAll = overwrite }
            }
            if overwrite { kept.append(job) } else { summary.skipped += 1 }
        }
        jobs = kept
        return true
    }

    private func run(_ jobs: [BatchJob], resizer: ImageResizer, summary initial: BatchSummary) {
        isRunning = true
        done = 0
        total = jobs.count
        currentName = ""
        summary = nil

        runTask = Task {
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Resizing images")
            defer { ProcessInfo.processInfo.endActivity(activity) }

            var summary = initial
            let start = Date()
            let width = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))

            await withTaskGroup(of: (BatchJob, String?).self) { group in
                var queue = jobs.makeIterator()
                for _ in 0..<width {
                    guard let job = queue.next() else { break }
                    group.addTask { (job, Self.perform(job, resizer)) }
                }
                while let (job, error) = await group.next() {
                    done += 1
                    currentName = job.displayName
                    if let error {
                        summary.failures.append((job.displayName, error))
                    } else if job.kind == .resize {
                        summary.resized += 1
                    } else {
                        summary.copied += 1
                    }
                    if Task.isCancelled {
                        summary.cancelled = true
                        group.cancelAll()
                        continue
                    }
                    if let next = queue.next() {
                        group.addTask { (next, Self.perform(next, resizer)) }
                    }
                }
            }

            summary.seconds = Date().timeIntervalSince(start)
            self.summary = summary
            isRunning = false
            notifyIfInBackground(summary)
        }
    }

    nonisolated private static func perform(_ job: BatchJob, _ resizer: ImageResizer) -> String? {
        do {
            switch job.kind {
            case .resize:
                try resizer.process(source: job.source, destination: job.destination)
            case .copy:
                let fm = FileManager.default
                try fm.createDirectory(at: job.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: job.destination.path) { try fm.removeItem(at: job.destination) }
                try fm.copyItem(at: job.source, to: job.destination)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Helpers

    private func notifyIfInBackground(_ s: BatchSummary) {
        guard !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = s.cancelled ? "Resizing stopped" : "Resizing complete"
            content.body = s.failures.isEmpty
                ? "\(s.resized) images resized. Click to open the folder."
                : "\(s.resized) images resized, \(s.failures.count) failed. Click to open the folder."
            content.userInfo = ["folder": s.destination.path]
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func alert(_ title: String, _ detail: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.runModal()
    }
}

enum OptionsStore {
    private static let key = "options"

    static func load() -> ResizeOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let options = try? JSONDecoder().decode(ResizeOptions.self, from: data)
        else { return ResizeOptions() }
        return options
    }

    static func save(_ options: ResizeOptions) {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static let presetsKey = "presets"

    static func loadLibrary() -> PresetLibrary {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let library = try? JSONDecoder().decode(PresetLibrary.self, from: data)
        else { return .starter }
        return library
    }

    static func save(_ library: PresetLibrary) {
        if let data = try? JSONEncoder().encode(library) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }
}

/// The user's real home folder. Inside the sandbox NSHomeDirectory() points
/// at the app's container instead.
func realHomeDirectory() -> String {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
        return String(cString: dir)
    }
    return NSHomeDirectory()
}

/// Resolves the saved watermark bookmark and holds sandbox access until stop().
final class WatermarkAccess {
    private(set) var url: URL?
    private(set) var refreshedBookmark: Data?
    private var accessing = false

    init(options: ResizeOptions) {
        guard options.watermarkPlacement != .none, let data = options.watermarkBookmark else { return }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return }
        accessing = resolved.startAccessingSecurityScopedResource()
        url = resolved
        if stale { refreshedBookmark = Self.bookmark(for: resolved) }
    }

    func stop() {
        if accessing { url?.stopAccessingSecurityScopedResource() }
        accessing = false
    }

    deinit { stop() }

    static func bookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData())
    }
}
