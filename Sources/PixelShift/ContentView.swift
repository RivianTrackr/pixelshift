import AppKit
import ResizeCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
            Divider()
            Form {
                presetSection
                filesSection
                resizeSection
                metadataSection
                watermarkSection
                outputSection
            }
            .formStyle(.grouped)
            .disabled(model.isRunning)
        }
        .frame(width: 480)
        .frame(minHeight: 760)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadURLs(providers) { model.process($0) }
            return true
        }
    }

    // MARK: Header: drop zone, progress or result

    @ViewBuilder private var header: some View {
        if model.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Resizing \(model.done) of \(model.total)")
                        .font(.headline)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { model.cancel() }
                }
                ProgressView(value: Double(model.done), total: Double(max(model.total, 1)))
                Text(model.currentName.isEmpty ? " " : model.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(height: 96)
        } else {
            VStack(spacing: 10) {
                dropZone
                if let s = model.summary { summaryRow(s) }
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.stack")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop images or folders here")
                .font(.headline)
            Button("Choose Files…") { model.chooseFilesAndProcess() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private func summaryRow(_ s: BatchSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: s.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(s.failures.isEmpty ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(summaryText(s))
                    .font(.callout)
                if !s.failures.isEmpty {
                    DisclosureGroup("\(s.failures.count) couldn’t be resized") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(s.failures.enumerated()), id: \.offset) { _, f in
                                    Text("\(f.name): \(f.message)")
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                    }
                    .font(.caption)
                }
            }
            Spacer()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([s.destination])
            }
            Button {
                model.summary = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
    }

    private func summaryText(_ s: BatchSummary) -> String {
        var parts = ["\(s.resized) resized"]
        if s.copied > 0 { parts.append("\(s.copied) copied") }
        if s.skipped > 0 { parts.append("\(s.skipped) skipped") }
        let time = s.seconds < 1 ? "under a second" : String(format: "%.1fs", s.seconds)
        return (s.cancelled ? "Stopped: " : "") + parts.joined(separator: ", ") + " in \(time)"
    }

    // MARK: Sections

    private var presetSection: some View {
        Section {
            LabeledContent("Preset") {
                Menu {
                    ForEach(model.library.presets) { preset in
                        Toggle(preset.name, isOn: Binding(
                            get: { preset.id == model.library.selectedID },
                            set: { _ in model.selectPreset(preset) }
                        ))
                    }
                    Divider()
                    Button("Save as New Preset…") { model.saveAsNewPreset() }
                    if let selected = model.library.selected {
                        Button("Update “\(selected.name)” with Current Settings") { model.updateSelectedPreset() }
                            .disabled(!model.presetIsModified)
                        Button("Rename “\(selected.name)”…") { model.renameSelectedPreset() }
                        Button("Delete “\(selected.name)”…") { model.deleteSelectedPreset() }
                    }
                } label: {
                    Text(presetLabel)
                }
                .fixedSize()
            }
        } footer: {
            if model.presetIsModified {
                Text("Settings changed since this preset was chosen. Use the preset menu to update it or save a new one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetLabel: String {
        guard let selected = model.library.selected else { return "Custom" }
        return model.presetIsModified ? "\(selected.name) (edited)" : selected.name
    }

    private var filesSection: some View {
        Section("Files") {
            Toggle("Copy non-image files", isOn: $model.options.copyNonImageFiles)
            Toggle("Ask before replacing existing files", isOn: $model.options.warnBeforeOverwriting)
        }
    }

    private var resizeSection: some View {
        Section("Resize") {
            Picker("Method", selection: $model.options.method) {
                ForEach(ResizeMethod.allCases) { Text($0.title).tag($0) }
            }
            let m = model.options.method
            if m.usesPercent {
                LabeledContent("Percent") {
                    numberField(value: $model.options.percent, suffix: "%")
                }
            }
            if m.usesWidth || m.usesHeight {
                LabeledContent(m == .crop || m == .cropThenFit ? "Size (aspect ratio)" : "Size") {
                    HStack(spacing: 6) {
                        if m.usesWidth {
                            numberField(value: $model.options.width, suffix: nil)
                        } else {
                            autoLabel
                        }
                        Text("×").foregroundStyle(.secondary)
                        if m.usesHeight {
                            numberField(value: $model.options.height, suffix: nil)
                        } else {
                            autoLabel
                        }
                        Text("px").foregroundStyle(.secondary)
                    }
                }
            }
            if m.canUpscale {
                Toggle("Scale down only", isOn: $model.options.scaleDownOnly)
            }
        }
    }

    private var metadataSection: some View {
        Section("Metadata") {
            Toggle("Copy metadata (camera, date, location)", isOn: $model.options.copyMetadata)
            Toggle("Add artist and copyright", isOn: $model.options.addArtistCopyright)
            if model.options.addArtistCopyright {
                TextField("Artist", text: $model.options.artist)
                TextField("Copyright", text: $model.options.copyright)
            }
            Toggle("Set DPI", isOn: $model.options.overwriteDPI)
            if model.options.overwriteDPI {
                LabeledContent("DPI") { numberField(value: $model.options.dpi, suffix: nil) }
            }
        }
    }

    private var watermarkSection: some View {
        Section("Watermark") {
            Picker("Position", selection: $model.options.watermarkPlacement) {
                ForEach(WatermarkPlacement.allCases) { p in
                    Text(p.title).tag(p)
                    if p == .none { Divider() }
                }
            }
            if model.options.watermarkPlacement != .none {
                LabeledContent("Image") {
                    HStack {
                        Text(watermarkName)
                            .foregroundStyle(model.options.watermarkPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseWatermark)
                    }
                }
                if model.options.watermarkPlacement != .stretch {
                    LabeledContent("Offset") {
                        HStack(spacing: 6) {
                            numberField(value: $model.options.watermarkDx, suffix: nil)
                            Text("×").foregroundStyle(.secondary)
                            numberField(value: $model.options.watermarkDy, suffix: "px")
                        }
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        Section("Output") {
            Picker("Format", selection: $model.options.format) {
                ForEach(OutputFormat.allCases) { Text($0.title).tag($0) }
            }
            Picker("Color space", selection: $model.options.colorSpace) {
                ForEach(OutputColorSpace.allCases) { Text($0.title).tag($0) }
            }
            if model.options.format.isLossy {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: qualityBinding, in: 1...100)
                            .frame(width: 180)
                        Text("\(model.options.quality)%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            ColorPicker(model.options.format.supportsAlpha ? "Background behind transparency" : "Fill for transparent areas",
                        selection: backgroundBinding, supportsOpacity: model.options.format.supportsAlpha)
        }
    }

    // MARK: Bindings and helpers

    private var qualityBinding: Binding<Double> {
        Binding(get: { Double(model.options.quality) },
                set: { model.options.quality = Int($0.rounded()) })
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: {
                let c = model.options.background
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
                model.options.background = RGBA(r: ns.redComponent, g: ns.greenComponent,
                                                b: ns.blueComponent, a: ns.alphaComponent)
            }
        )
    }

    private var autoLabel: some View {
        Text("auto")
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
            .help("Follows the original proportions")
    }

    private var watermarkName: String {
        guard let p = model.options.watermarkPath, !p.isEmpty else { return "None chosen" }
        return (p as NSString).lastPathComponent
    }

    private func chooseWatermark() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a watermark image (PNG with transparency works best)"
        if panel.runModal() == .OK, let url = panel.url {
            model.options.watermarkPath = url.path
            model.options.watermarkBookmark = WatermarkAccess.bookmark(for: url)
        }
    }

    private func numberField(value: Binding<Int>, suffix: String?) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .labelsHidden()
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
    }

    private func numberField(value: Binding<Double>, suffix: String?) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number.grouping(.never).precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .labelsHidden()
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
    }

    private func loadURLs(_ providers: [NSItemProvider], then handle: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            handle(urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
        }
    }
}
