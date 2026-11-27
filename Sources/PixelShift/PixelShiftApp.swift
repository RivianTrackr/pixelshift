import AppKit
import SwiftUI
import UserNotifications

@main
struct PixelShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("PixelShift", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 480, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
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
    }
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
