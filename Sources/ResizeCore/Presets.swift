import Foundation

public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var options: ResizeOptions

    public init(id: UUID = UUID(), name: String, options: ResizeOptions) {
        self.id = id
        self.name = name
        self.options = options.settingsOnly
    }
}

extension ResizeOptions {
    /// The options a preset stores: everything except where files were last saved.
    public var settingsOnly: ResizeOptions {
        var copy = self
        copy.lastDestination = nil
        return copy
    }

    /// Applies a preset's settings, keeping the remembered destination folder.
    public func applying(_ preset: Preset) -> ResizeOptions {
        var next = preset.options
        next.lastDestination = lastDestination
        return next
    }
}

public struct PresetLibrary: Codable, Equatable, Sendable {
    public var presets: [Preset]
    public var selectedID: UUID?

    public init(presets: [Preset], selectedID: UUID?) {
        self.presets = presets
        self.selectedID = selectedID
    }

    /// First-run presets: the settings carried over from Resize Master, plus a square crop.
    public static var starter: PresetLibrary {
        let web = Preset(name: "Web, 1200 tall", options: ResizeOptions())
        var square = ResizeOptions()
        square.method = .cropThenFit
        square.width = 1080
        square.height = 1080
        square.quality = 85
        return PresetLibrary(presets: [web, Preset(name: "Square 1080", options: square)], selectedID: web.id)
    }

    public var selected: Preset? { presets.first { $0.id == selectedID } }

    public func isModified(_ current: ResizeOptions) -> Bool {
        guard let selected else { return false }
        return selected.options != current.settingsOnly
    }

    @discardableResult
    public mutating func add(name: String, options: ResizeOptions) -> Preset {
        let preset = Preset(name: uniqueName(name), options: options)
        presets.append(preset)
        selectedID = preset.id
        return preset
    }

    public mutating func updateSelected(with options: ResizeOptions) {
        guard let i = presets.firstIndex(where: { $0.id == selectedID }) else { return }
        presets[i].options = options.settingsOnly
    }

    public mutating func renameSelected(to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == selectedID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != presets[i].name else { return }
        presets[i].name = uniqueName(trimmed)
    }

    public mutating func deleteSelected() {
        guard let i = presets.firstIndex(where: { $0.id == selectedID }) else { return }
        presets.remove(at: i)
        selectedID = nil
    }

    private func uniqueName(_ name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Preset" : name
        let taken = Set(presets.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
