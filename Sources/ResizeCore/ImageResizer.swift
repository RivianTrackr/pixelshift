import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ResizeError: LocalizedError {
    case cannotRead
    case cannotRender
    case cannotWrite
    case cannotLoadWatermark(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRead: "The file couldn’t be read as an image."
        case .cannotRender: "The image couldn’t be resized."
        case .cannotWrite: "The resized image couldn’t be saved."
        case .cannotLoadWatermark(let path): "The watermark image at \(path) couldn’t be opened."
        }
    }
}

/// Resizes one image file to another using the given options.
/// Thread-safe: one instance can process many files concurrently.
public final class ImageResizer: @unchecked Sendable {
    public let options: ResizeOptions
    private let watermark: CGImage?
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init(options: ResizeOptions) throws {
        self.options = options
        if options.watermarkPlacement != .none, let path = options.watermarkPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Self.decodeUpright(src)
            else { throw ResizeError.cannotLoadWatermark(path) }
            watermark = image
        } else {
            watermark = nil
        }
    }

    public func process(source: URL, destination: URL) throws {
        try autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(src) > 0,
                  let image = Self.decodeUpright(src)
            else { throw ResizeError.cannotRead }

            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
            let plan = ResizePlan.make(sourceWidth: image.width, sourceHeight: image.height, options: options)
            let output = try render(image, plan: plan)
            try write(output, sourceProperties: props, to: destination)
        }
    }

    // MARK: Decode

    /// Decodes the first image with its EXIF orientation applied.
    static func decodeUpright(_ src: CGImageSource) -> CGImage? {
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        guard orientation > 1 && orientation <= 8 else { return image }

        let ci = CIImage(cgImage: image).oriented(forExifOrientation: orientation)
        let format: CIFormat = image.bitsPerComponent > 8 ? .RGBA16 : .RGBA8
        return ciContext.createCGImage(ci, from: ci.extent, format: format, colorSpace: rgbSpace(of: image))
    }

    static func rgbSpace(of image: CGImage) -> CGColorSpace {
        if let cs = image.colorSpace, cs.model == .rgb { return cs }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    // MARK: Render

    func render(_ image: CGImage, plan: ResizePlan) throws -> CGImage {
        let outW = plan.outputWidth
        let outH = plan.outputHeight
        let space: CGColorSpace = switch options.colorSpace {
        case .original: Self.rgbSpace(of: image)
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        }

        let keepsAlpha = options.format.supportsAlpha
        let deep = image.bitsPerComponent > 8 && (options.format == .png || options.format == .tiff)
        let alphaInfo: CGImageAlphaInfo = keepsAlpha ? .premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: deep ? 16 : 8, bytesPerRow: 0,
            space: space, bitmapInfo: alphaInfo.rawValue
        ) else { throw ResizeError.cannotRender }

        ctx.interpolationQuality = .high
        let canvas = CGRect(x: 0, y: 0, width: outW, height: outH)

        // Transparent areas take the background color; JPEG has no alpha, so
        // the background is always painted opaque there.
        let bg = options.background
        let bgAlpha = keepsAlpha ? bg.a : 1
        if bgAlpha > 0 {
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            ctx.setFillColor(CGColor(colorSpace: srgb, components: [bg.r, bg.g, bg.b, bgAlpha])!)
            ctx.fill(canvas)
        }

        let fullRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let source = plan.crop == fullRect ? image : (image.cropping(to: plan.crop) ?? image)
        ctx.draw(source, in: canvas)

        if let wm = watermark, options.watermarkPlacement != .none {
            ctx.draw(wm, in: watermarkRect(watermarkWidth: wm.width, watermarkHeight: wm.height,
                                           canvasWidth: outW, canvasHeight: outH))
        }

        guard let out = ctx.makeImage() else { throw ResizeError.cannotRender }
        return out
    }

    /// Watermark frame in Core Graphics (bottom-left origin) coordinates.
    /// Offsets push the mark inward from the edge it is anchored to.
    func watermarkRect(watermarkWidth: Int, watermarkHeight: Int, canvasWidth: Int, canvasHeight: Int) -> CGRect {
        let W = Double(canvasWidth), H = Double(canvasHeight)
        let p = options.watermarkPlacement
        if p == .stretch { return CGRect(x: 0, y: 0, width: W, height: H) }

        // Never let the mark be larger than the picture.
        let s = min(1, W / Double(watermarkWidth), H / Double(watermarkHeight))
        let ww = Double(watermarkWidth) * s
        let wh = Double(watermarkHeight) * s
        let dx = Double(options.watermarkDx)
        let dy = Double(options.watermarkDy)

        let x: Double = switch p {
        case .topLeft, .left, .bottomLeft: dx
        case .top, .center, .bottom: (W - ww) / 2 + dx
        default: W - ww - dx
        }
        let yFromTop: Double = switch p {
        case .topLeft, .top, .topRight: dy
        case .left, .center, .right: (H - wh) / 2 + dy
        default: H - wh - dy
        }
        return CGRect(x: x, y: H - yFromTop - wh, width: ww, height: wh)
    }

    // MARK: Write

    func write(_ image: CGImage, sourceProperties: [CFString: Any], to destination: URL) throws {
        let fm = FileManager.default
        let dir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write next to the target, then swap in, so a failed save never
        // leaves a half-written file (or destroys the original when the
        // destination is the source itself).
        let name = ".pixelshift-\(UUID().uuidString).\(options.format.fileExtension)"
        let props = outputProperties(from: sourceProperties, width: image.width, height: image.height)

        let besideTarget = dir.appendingPathComponent(name)
        if encode(image, props, to: besideTarget) {
            do {
                if fm.fileExists(atPath: destination.path) {
                    _ = try fm.replaceItemAt(destination, withItemAt: besideTarget)
                } else {
                    try fm.moveItem(at: besideTarget, to: destination)
                }
                return
            } catch {
                try? fm.removeItem(at: besideTarget)
                throw error
            }
        }

        // The folder isn't writable to us (in the sandbox: only the file itself
        // was granted). Encode in our own temp folder, then write the bytes over
        // the existing file, which needs access to that file alone.
        let scratch = fm.temporaryDirectory.appendingPathComponent(name)
        defer { try? fm.removeItem(at: scratch) }
        guard encode(image, props, to: scratch), fm.fileExists(atPath: destination.path) else {
            throw ResizeError.cannotWrite
        }
        let data = try Data(contentsOf: scratch)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
    }

    private func encode(_ image: CGImage, _ props: [CFString: Any], to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, options.format.utType.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    func outputProperties(from source: [CFString: Any], width: Int, height: Int) -> [CFString: Any] {
        var props: [CFString: Any] = [:]

        if options.copyMetadata {
            props = source
            for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth,
                        kCGImagePropertyHasAlpha, kCGImagePropertyColorModel, kCGImagePropertyProfileName,
                        kCGImagePropertyIsFloat, kCGImagePropertyIsIndexed, kCGImagePropertyPrimaryImage] {
                props.removeValue(forKey: key)
            }
            if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = width
                exif[kCGImagePropertyExifPixelYDimension] = height
                props[kCGImagePropertyExifDictionary] = exif
            }
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
        } else {
            // Without metadata, still carry the print resolution.
            if let dpi = source[kCGImagePropertyDPIWidth] { props[kCGImagePropertyDPIWidth] = dpi }
            if let dpi = source[kCGImagePropertyDPIHeight] { props[kCGImagePropertyDPIHeight] = dpi }
        }

        // Pixels are already upright.
        props[kCGImagePropertyOrientation] = 1

        if options.overwriteDPI {
            props[kCGImagePropertyDPIWidth] = options.dpi
            props[kCGImagePropertyDPIHeight] = options.dpi
            var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFXResolution] = options.dpi
            tiff[kCGImagePropertyTIFFYResolution] = options.dpi
            tiff[kCGImagePropertyTIFFResolutionUnit] = 2
            props[kCGImagePropertyTIFFDictionary] = tiff
        }

        if options.addArtistCopyright {
            var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            var iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            if !options.artist.isEmpty {
                tiff[kCGImagePropertyTIFFArtist] = options.artist
                iptc[kCGImagePropertyIPTCByline] = [options.artist]
            }
            if !options.copyright.isEmpty {
                tiff[kCGImagePropertyTIFFCopyright] = options.copyright
                iptc[kCGImagePropertyIPTCCopyrightNotice] = options.copyright
            }
            props[kCGImagePropertyTIFFDictionary] = tiff
            props[kCGImagePropertyIPTCDictionary] = iptc
        }

        if options.format.isLossy {
            props[kCGImageDestinationLossyCompressionQuality] = Double(min(max(options.quality, 1), 100)) / 100
        }
        return props
    }
}
