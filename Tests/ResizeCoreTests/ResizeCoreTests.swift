import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ResizeCore

private func opts(_ method: ResizeMethod, w: Int = 1600, h: Int = 1200, pct: Double = 100, down: Bool = true) -> ResizeOptions {
    var o = ResizeOptions()
    o.method = method; o.width = w; o.height = h; o.percent = pct; o.scaleDownOnly = down
    return o
}

private func size(_ p: ResizePlan) -> [Int] { [p.outputWidth, p.outputHeight] }

@Suite struct PlanTests {
    @Test func scaleByHeight() {
        #expect(size(.make(sourceWidth: 4000, sourceHeight: 3000, options: opts(.height))) == [1600, 1200])
    }

    @Test func scaleDownOnlyKeepsSmallImages() {
        #expect(size(.make(sourceWidth: 800, sourceHeight: 600, options: opts(.height))) == [800, 600])
        #expect(size(.make(sourceWidth: 800, sourceHeight: 600, options: opts(.height, down: false))) == [1600, 1200])
    }

    @Test func scaleByWidthAndPercent() {
        #expect(size(.make(sourceWidth: 3000, sourceHeight: 2000, options: opts(.width, w: 1500))) == [1500, 1000])
        #expect(size(.make(sourceWidth: 3000, sourceHeight: 2000, options: opts(.percent, pct: 25))) == [750, 500])
    }

    @Test func fitToRectangle() {
        // Portrait into a landscape box is limited by height.
        #expect(size(.make(sourceWidth: 3000, sourceHeight: 4000, options: opts(.fit, w: 1600, h: 1200))) == [900, 1200])
        #expect(size(.make(sourceWidth: 4000, sourceHeight: 1000, options: opts(.fit, w: 1600, h: 1200))) == [1600, 400])
    }

    @Test func cropToAspectRatio() {
        let p = ResizePlan.make(sourceWidth: 4000, sourceHeight: 3000, options: opts(.crop, w: 1, h: 1))
        #expect(p.crop == CGRect(x: 500, y: 0, width: 3000, height: 3000))
        #expect(size(p) == [3000, 3000])
    }

    @Test func cropThenFit() {
        let p = ResizePlan.make(sourceWidth: 3000, sourceHeight: 4000, options: opts(.cropThenFit, w: 1920, h: 1080))
        #expect(p.crop.width == 3000)
        #expect(p.crop.height == 1688)
        #expect(size(p) == [1920, 1080])
    }

    @Test func doNotResize() {
        #expect(size(.make(sourceWidth: 123, sourceHeight: 45, options: opts(.none))) == [123, 45])
    }

    @Test func validation() {
        var o = opts(.fit, w: 0, h: 10)
        #expect(o.validationError != nil)
        o.width = 10
        #expect(o.validationError == nil)
        o.watermarkPlacement = .center
        #expect(o.validationError != nil)
    }

    @Test func oldSettingsStillDecode() throws {
        let json = #"{"method":4,"width":800}"#.data(using: .utf8)!
        let o = try JSONDecoder().decode(ResizeOptions.self, from: json)
        #expect(o.method == .fit)
        #expect(o.width == 800)
        #expect(o.quality == 70)
    }
}

// MARK: - End to end

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("resizer-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a test image: left half red, right half blue, top 10% transparent.
private func writeImage(_ url: URL, width: Int, height: Int, type: CFString, orientation: Int = 1, extra: [CFString: Any] = [:]) throws {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height * 9 / 10))
    ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height * 9 / 10))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)!
    var props = extra
    props[kCGImagePropertyOrientation] = orientation
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
}

private func read(_ url: URL) -> (CGImage, [CFString: Any]) {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return (CGImageSourceCreateImageAtIndex(src, 0, nil)!,
            CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any])
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return px
}

@Suite struct EndToEndTests {
    @Test func pngToJpegWithTransparencyAndTags() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("in.png")
        try writeImage(src, width: 400, height: 300, type: "public.png" as CFString)

        var o = opts(.height, h: 150)
        o.addArtistCopyright = true
        o.artist = "Test Artist"
        o.copyright = "© Test"
        o.overwriteDPI = true
        o.dpi = 300
        o.background = RGBA(r: 1, g: 1, b: 1, a: 0)
        let out = dir.appendingPathComponent("out.jpg")
        try ImageResizer(options: o).process(source: src, destination: out)

        let (img, props) = read(out)
        #expect(img.width == 200 && img.height == 150)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFArtist] as? String == "Test Artist")
        #expect(tiff?[kCGImagePropertyTIFFCopyright] as? String == "© Test")
        #expect((props[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == 300)
        // Transparent top strip became white in the JPEG.
        let top = pixel(img, x: 100, y: 2)
        #expect(top[0] > 240 && top[1] > 240 && top[2] > 240)
        // Left is red, right is blue.
        let left = pixel(img, x: 20, y: 100), right = pixel(img, x: 180, y: 100)
        #expect(left[0] > 200 && left[2] < 60)
        #expect(right[2] > 200 && right[0] < 60)
    }

    @Test func appliesOrientation() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("rotated.jpg")
        // Stored 400x300, orientation 6 = displayed rotated 90° clockwise (300x400).
        try writeImage(src, width: 400, height: 300, type: "public.jpeg" as CFString, orientation: 6)
        let out = dir.appendingPathComponent("out.png")
        var o = opts(.none)
        o.format = .png
        try ImageResizer(options: o).process(source: src, destination: out)
        let (img, props) = read(out)
        #expect(img.width == 300 && img.height == 400)
        #expect((props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 == 1)
    }

    @Test func metadataIsStrippedUnlessCopied() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("gps.jpg")
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 30.27, kCGImagePropertyGPSLatitudeRef: "N"]
        try writeImage(src, width: 200, height: 200, type: "public.jpeg" as CFString,
                       extra: [kCGImagePropertyGPSDictionary: gps])

        let stripped = dir.appendingPathComponent("a.jpg")
        try ImageResizer(options: opts(.none)).process(source: src, destination: stripped)
        #expect(read(stripped).1[kCGImagePropertyGPSDictionary] == nil)

        var o = opts(.none)
        o.copyMetadata = true
        let kept = dir.appendingPathComponent("b.jpg")
        try ImageResizer(options: o).process(source: src, destination: kept)
        #expect(read(kept).1[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func overwritesSourceSafely() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("same.jpg")
        try writeImage(src, width: 400, height: 400, type: "public.jpeg" as CFString)
        try ImageResizer(options: opts(.width, w: 100)).process(source: src, destination: src)
        #expect(read(src).0.width == 100)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".pixelshift-") }
        #expect(leftovers.isEmpty)
    }

    @Test func watermarkBottomRight() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("photo.png")
        try writeImage(src, width: 400, height: 400, type: "public.png" as CFString)
        // Solid green 50x50 mark.
        let wmURL = dir.appendingPathComponent("mark.png")
        let ctx = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        let d = CGImageDestinationCreateWithURL(wmURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(d)

        var o = opts(.none)
        o.format = .png
        o.watermarkPlacement = .bottomRight
        o.watermarkPath = wmURL.path
        o.watermarkDx = 10
        o.watermarkDy = 10
        let out = dir.appendingPathComponent("out.png")
        try ImageResizer(options: o).process(source: src, destination: out)
        let img = read(out).0
        let inMark = pixel(img, x: 400 - 10 - 25, y: 400 - 10 - 25)
        #expect(inMark[1] > 200 && inMark[0] < 50)
        let outside = pixel(img, x: 395, y: 395)
        #expect(outside[1] < 50)
    }
}

@Suite struct JobTests {
    @Test func foldersKeepStructureAndRenameExtensions() throws {
        let root = try tempDir()
        let album = root.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: album.appendingPathComponent("Day 2"), withIntermediateDirectories: true)
        try writeImage(album.appendingPathComponent("a.png"), width: 10, height: 10, type: "public.png" as CFString)
        try writeImage(album.appendingPathComponent("Day 2/b.tif"), width: 10, height: 10, type: "public.tiff" as CFString)
        try Data("notes".utf8).write(to: album.appendingPathComponent("notes.txt"))
        try Data().write(to: album.appendingPathComponent(".DS_Store"))
        let loose = root.appendingPathComponent("loose.jpg")
        try writeImage(loose, width: 10, height: 10, type: "public.jpeg" as CFString)

        let out = URL(fileURLWithPath: "/tmp/out")
        let jobs = BatchJobs.collect(from: [album, loose], into: out, format: .jpeg, copyNonImageFiles: true)
        #expect(jobs.map(\.displayName) == ["Album/a.jpg", "Album/notes.txt", "Album/Day 2/b.jpg", "loose.jpg"]
                || Set(jobs.map(\.displayName)) == ["Album/a.jpg", "Album/notes.txt", "Album/Day 2/b.jpg", "loose.jpg"])
        #expect(jobs.first { $0.displayName == "Album/notes.txt" }?.kind == .copy)

        let noCopies = BatchJobs.collect(from: [album], into: out, format: .png, copyNonImageFiles: false)
        #expect(Set(noCopies.map(\.displayName)) == ["Album/a.png", "Album/Day 2/b.png"])
    }

    @Test func clashingNamesGetSuffix() throws {
        let root = try tempDir()
        try writeImage(root.appendingPathComponent("photo.png"), width: 10, height: 10, type: "public.png" as CFString)
        try writeImage(root.appendingPathComponent("photo.tif"), width: 10, height: 10, type: "public.tiff" as CFString)
        let jobs = BatchJobs.collect(from: [root.appendingPathComponent("photo.png"), root.appendingPathComponent("photo.tif")],
                                     into: URL(fileURLWithPath: "/tmp/out"), format: .jpeg, copyNonImageFiles: true)
        #expect(jobs.map(\.displayName) == ["photo.jpg", "photo 2.jpg"])
    }
}

@Suite struct PresetTests {
    @Test func starterMatchesCarriedOverSettings() {
        let lib = PresetLibrary.starter
        #expect(lib.selected?.name == "Web, 1200 tall")
        #expect(lib.selected?.options == ResizeOptions())
        #expect(!lib.isModified(ResizeOptions()))
    }

    @Test func destinationDoesNotCountAsAnEdit() {
        var o = ResizeOptions()
        o.lastDestination = "/Users/someone/Desktop"
        #expect(!PresetLibrary.starter.isModified(o))
        o.quality = 90
        #expect(PresetLibrary.starter.isModified(o))
    }

    @Test func applyingKeepsDestination() {
        var current = ResizeOptions()
        current.lastDestination = "/tmp/out"
        let square = PresetLibrary.starter.presets[1]
        let next = current.applying(square)
        #expect(next.method == .cropThenFit)
        #expect(next.lastDestination == "/tmp/out")
    }

    @Test func addUpdateRenameDelete() {
        var lib = PresetLibrary.starter
        var o = ResizeOptions()
        o.format = .png
        let added = lib.add(name: "Square 1080", options: o)
        #expect(added.name == "Square 1080 2")
        #expect(lib.selectedID == added.id)

        o.quality = 50
        #expect(lib.isModified(o))
        lib.updateSelected(with: o)
        #expect(!lib.isModified(o))

        lib.renameSelected(to: "  Archive PNG ")
        #expect(lib.selected?.name == "Archive PNG")

        lib.deleteSelected()
        #expect(lib.presets.count == 2)
        #expect(lib.selected == nil)
    }
}

@Suite struct SandboxFallbackTests {
    @Test func replacesFileWhenFolderIsNotWritable() throws {
        let dir = try tempDir()
        let file = dir.appendingPathComponent("locked.jpg")
        try writeImage(file, width: 400, height: 400, type: "public.jpeg" as CFString)
        // Folder read-only, file still writable: like a sandbox grant for the file alone.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        try ImageResizer(options: opts(.width, w: 100)).process(source: file, destination: file)
        #expect(read(file).0.width == 100)
    }
}
