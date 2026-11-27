import SwiftUI

/// PixelShift → Settings… (⌘,).
struct SettingsView: View {
    @Bindable var updates: Updates

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
                Toggle("Download and install updates automatically", isOn: $updates.automaticDownloads)
                    .disabled(!updates.automaticChecks)
                LabeledContent("Version", value: version)
                LabeledContent("Last checked") {
                    Text(updates.lastChecked.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                }
                HStack {
                    Spacer()
                    Button("Check Now") { updates.check() }
                        .disabled(!updates.canCheck)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { updates.refresh() }
    }
}
