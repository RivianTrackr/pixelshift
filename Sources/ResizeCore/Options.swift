import Foundation
import UniformTypeIdentifiers

public enum ResizeMethod: Int, CaseIterable, Codable, Sendable, Identifiable {
    case none, percent, width, height, fit, crop, cropThenFit

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .none: "Do not resize"
        case .percent: "Scale by percent"
        case .width: "Scale by width"
        case .height: "Scale by height"
        case .fit: "Fit to rectangle"
        case .crop: "Crop to aspect ratio"
        case .cropThenFit: "Crop to aspect ratio, then fit"
        }
    }

    public var usesWidth: Bool { [.width, .fit, .crop, .cropThenFit].contains(self) }
    public var usesHeight: Bool { [.height, .fit, .crop, .cropThenFit].contains(self) }
    public var usesPercent: Bool { self == .percent }
    public var canUpscale: Bool { ![.none, .crop].contains(self) }
}

public enum WatermarkPlacement: Int, CaseIterable, Codable, Sendable, Identifiable {
    case none, topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight, stretch

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .none: "No watermark"
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        case .stretch: "Center (stretch)"
        }
    }
}

public enum OutputFormat: Int, CaseIterable, Codable, Sendable, Identifiable {
    case jpeg, png, tiff, heic

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .tiff: "TIFF"
        case .heic: "HEIC"
        }
    }

    public var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .tiff: .tiff
        case .heic: .heic
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .tiff: "tif"
        case .heic: "heic"
        }
    }

    public var isLossy: Bool { self == .jpeg || self == .heic }
    public var supportsAlpha: Bool { self != .jpeg }
}

public enum OutputColorSpace: Int, CaseIterable, Codable, Sendable, Identifiable {
    case original, sRGB, displayP3, adobeRGB

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .original: "Original color space"
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .adobeRGB: "Adobe RGB (1998)"
        }
    }
}

public struct RGBA: Codable, Equatable, Sendable {
    public var r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// Every setting the window exposes. Defaults match the Resize Master
/// settings that were in use when this app replaced it.
public struct ResizeOptions: Codable, Equatable, Sendable {
    public var copyNonImageFiles = true
    public var warnBeforeOverwriting = false

    public var method: ResizeMethod = .height
    public var width = 1600
    public var height = 1200
    public var percent = 100.0
    public var scaleDownOnly = true

    public var copyMetadata = false
    public var addArtistCopyright = false
    public var artist = ""
    public var copyright = ""
    public var overwriteDPI = false
    public var dpi = 72

    public var watermarkPlacement: WatermarkPlacement = .none
    public var watermarkPath: String?
    /// Security-scoped bookmark for the watermark, so a sandboxed build can
    /// reopen it on later launches. The path is kept for display.
    public var watermarkBookmark: Data?
    public var watermarkDx = 0
    public var watermarkDy = 0

    public var background = RGBA(r: 1, g: 1, b: 1, a: 0)
    public var format: OutputFormat = .jpeg
    public var colorSpace: OutputColorSpace = .original
    public var quality = 70

    public var lastDestination: String?

    public init() {}

    /// A message for the first setting that would make resizing fail, or nil.
    public var validationError: String? {
        if method.usesWidth && method.usesHeight && (width <= 0 || height <= 0) {
            return "Width and height must be greater than zero."
        }
        if method.usesWidth && width <= 0 { return "Width must be greater than zero." }
        if method.usesHeight && height <= 0 { return "Height must be greater than zero." }
        if method.usesPercent && percent <= 0 { return "Percent must be greater than zero." }
        if overwriteDPI && dpi <= 0 { return "DPI must be greater than zero." }
        if watermarkPlacement != .none && (watermarkPath ?? "").isEmpty {
            return "Choose a watermark image, or set the watermark to None."
        }
        return nil
    }
}

extension ResizeOptions {
    // Decode field by field so settings saved by an older build still load
    // after new fields are added.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ current: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? current
        }
        copyNonImageFiles = v(.copyNonImageFiles, copyNonImageFiles)
        warnBeforeOverwriting = v(.warnBeforeOverwriting, warnBeforeOverwriting)
        method = v(.method, method)
        width = v(.width, width)
        height = v(.height, height)
        percent = v(.percent, percent)
        scaleDownOnly = v(.scaleDownOnly, scaleDownOnly)
        copyMetadata = v(.copyMetadata, copyMetadata)
        addArtistCopyright = v(.addArtistCopyright, addArtistCopyright)
        artist = v(.artist, artist)
        copyright = v(.copyright, copyright)
        overwriteDPI = v(.overwriteDPI, overwriteDPI)
        dpi = v(.dpi, dpi)
        watermarkPlacement = v(.watermarkPlacement, watermarkPlacement)
        watermarkPath = v(.watermarkPath, watermarkPath)
        watermarkBookmark = v(.watermarkBookmark, watermarkBookmark)
        watermarkDx = v(.watermarkDx, watermarkDx)
        watermarkDy = v(.watermarkDy, watermarkDy)
        background = v(.background, background)
        format = v(.format, format)
        colorSpace = v(.colorSpace, colorSpace)
        quality = v(.quality, quality)
        lastDestination = v(.lastDestination, lastDestination)
    }
}
