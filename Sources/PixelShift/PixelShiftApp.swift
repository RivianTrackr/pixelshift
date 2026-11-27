import AppKit
import Sparkle
import SwiftUI
import UserNotifications

@main
struct PixelShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @State private var updates = Updates()

    var body: some Scene {
        Window("PixelShift", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 480, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.chooseFilesAndProcess() }
                    .keyboardShortcut("o")
                    .disabled(model.isRunning)
            }
            CommandMenu("Presets") {
                Group {
                    ForEach(Array(model.library.presets.enumerated()), id: \.element.id) { index, preset in
                        let button = Toggle(preset.name, isOn: Binding(
                            get: { preset.id == model.library.selectedID },
                            set: { _ in model.selectPreset(preset) }
                        ))
                        if index < 9 {
                            button.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        } else {
                            button
                        }
                    }
                    Divider()
                    Button("Save as New Preset…") { model.saveAsNewPreset() }
                    Button("Update Preset with Current Settings") { model.updateSelectedPreset() }
                        .disabled(!model.presetIsModified)
                }
                .disabled(model.isRunning)
            }
        }

        Settings {
            SettingsView(updates: updates)
        }
    }
}

/// Sparkle updater for copies downloaded from the web. Reads SUFeedURL and
/// SUPublicEDKey from Info.plist; asks the user about automatic checks on second launch.
@MainActor @Observable
final class Updates {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private(set) var canCheck = false
    private var observation: NSKeyValueObservation?

    /// Mirrors Sparkle's own settings so the Settings window can change them,
    /// including after the first-run "check automatically?" question.
    var automaticChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticChecks }
    }
    var automaticDownloads: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticDownloads }
    }

    init() {
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        automaticDownloads = controller.updater.automaticallyDownloadsUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    /// Re-reads Sparkle's settings (its first-run question may have changed them).
    func refresh() {
        if automaticChecks != controller.updater.automaticallyChecksForUpdates {
            automaticChecks = controller.updater.automaticallyChecksForUpdates
        }
        if automaticDownloads != controller.updater.automaticallyDownloadsUpdates {
            automaticDownloads = controller.updater.automaticallyDownloadsUpdates
        }
    }

    var lastChecked: Date? { controller.updater.lastUpdateCheckDate }

    func check() { controller.checkForUpdates(nil) }
}

/// Backs the "Resize with PixelShift" item in Finder's right-click menu
/// (declared under NSServices in Info.plist). Uses the window's current settings.
final class FinderService: NSObject {
    @objc func resizeWithPixelShift(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were selected." as NSString
            return
        }
        Task { @MainActor in AppModel.shared.process(urls) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let services = FinderService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Files or folders dropped on the Dock icon or sent with Open With.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.process(urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            AppModel.shared.isRunning ? AppModel.shared.confirmQuitWhileRunning() : .terminateNow
        }
    }

    // Clicking the "done" notification opens the results folder.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let path = response.notification.request.content.userInfo["folder"] as? String {
            await MainActor.run { _ = NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
