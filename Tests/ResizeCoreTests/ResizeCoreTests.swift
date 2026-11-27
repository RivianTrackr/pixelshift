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
        o.metadata = .keepAll
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

@Suite struct OverwriteGuardTests {
    @Test func savingIntoTheSameFolderIsCaught() throws {
        let dir = try tempDir()
        let photo = dir.appendingPathComponent("photo.jpg")
        let other = dir.appendingPathComponent("other.JPEG")
        try writeImage(photo, width: 10, height: 10, type: "public.jpeg" as CFString)
        try writeImage(other, width: 10, height: 10, type: "public.jpeg" as CFString)
        let jobs = BatchJobs.collect(from: [photo, other], into: dir, format: .jpeg, copyNonImageFiles: false)
        // photo.jpg lands on itself; other.JPEG becomes other.jpg, a new file.
        #expect(BatchJobs.replacingOriginals(jobs).map(\.source.lastPathComponent) == ["photo.jpg"])
    }

    @Test func droppedFolderSavedToItsParentIsCaught() throws {
        let dir = try tempDir()
        let trip = dir.appendingPathComponent("Trip")
        try FileManager.default.createDirectory(at: trip, withIntermediateDirectories: true)
        try writeImage(trip.appendingPathComponent("a.jpg"), width: 10, height: 10, type: "public.jpeg" as CFString)
        let jobs = BatchJobs.collect(from: [trip], into: dir, format: .jpeg, copyNonImageFiles: false)
        #expect(BatchJobs.replacingOriginals(jobs).count == 1)
    }

    @Test func anotherDroppedFileIsCaught() throws {
        let dir = try tempDir()
        let png = dir.appendingPathComponent("photo.png")
        let jpg = dir.appendingPathComponent("photo.jpg")
        try writeImage(png, width: 10, height: 10, type: "public.png" as CFString)
        try writeImage(jpg, width: 10, height: 10, type: "public.jpeg" as CFString)
        let jobs = BatchJobs.collect(from: [png, jpg], into: dir, format: .jpeg, copyNonImageFiles: false)
        // Clashing outputs are numbered ("photo 2.jpg"), but one of them is still photo.jpg itself.
        #expect(BatchJobs.replacingOriginals(jobs).count == 1)
    }

    @Test func otherFoldersAndSuffixesAreFine() throws {
        let dir = try tempDir()
        let photo = dir.appendingPathComponent("photo.jpg")
        try writeImage(photo, width: 10, height: 10, type: "public.jpeg" as CFString)
        let elsewhere = BatchJobs.collect(from: [photo], into: try tempDir(), format: .jpeg, copyNonImageFiles: false)
        #expect(BatchJobs.replacingOriginals(elsewhere).isEmpty)
        let suffixed = BatchJobs.collect(from: [photo], placement: .folder(dir), format: .jpeg, suffix: "-1200", copyNonImageFiles: false)
        #expect(BatchJobs.replacingOriginals(suffixed).isEmpty)
    }
}

@Suite struct LargeImageTests {
    @Test func bigPhotoDecodesSmallAndStaysCorrect() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("big.jpg")
        // Stored 4000x3000, orientation 6: displayed 3000x4000.
        try writeImage(src, width: 4000, height: 3000, type: "public.jpeg" as CFString, orientation: 6)
        let out = dir.appendingPathComponent("out.png")
        var o = opts(.height, h: 400)
        o.format = .png
        let resizer = try ImageResizer(options: o)
        let source = CGImageSourceCreateWithURL(src as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        let (decoded, _) = try #require(try resizer.decode(source, props))
        #expect(max(decoded.width, decoded.height) <= 800)   // not 4000

        try resizer.process(source: src, destination: out)
        let (img, _) = read(out)
        #expect(img.width == 300 && img.height == 400)
    }

    @Test func cropStillLandsInTheMiddle() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("wide.png")
        try writeImage(src, width: 4000, height: 2000, type: "public.png" as CFString)
        let out = dir.appendingPathComponent("out.png")
        var o = opts(.cropThenFit, w: 100, h: 100)
        o.format = .png
        try ImageResizer(options: o).process(source: src, destination: out)
        let (img, _) = read(out)
        #expect(img.width == 100 && img.height == 100)
        // Centered square of a red | blue image: red on the left, blue on the right.
        #expect(pixel(img, x: 10, y: 50)[0] > 200 && pixel(img, x: 10, y: 50)[2] < 50)
        #expect(pixel(img, x: 90, y: 50)[2] > 200 && pixel(img, x: 90, y: 50)[0] < 50)
    }

    @Test func absurdSizesFailClearly() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("p.jpg")
        try writeImage(src, width: 4000, height: 3000, type: "public.jpeg" as CFString)
        let o = opts(.percent, pct: 2000, down: false)   // 80000 x 60000
        #expect(throws: ResizeError.self) {
            try ImageResizer(options: o).process(source: src, destination: dir.appendingPathComponent("o.jpg"))
        }
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

@Suite struct InPlaceWriteTests {
    struct Boom: Error {}

    @Test func failedOverwriteRestoresTheOriginal() throws {
        let dir = try tempDir()
        let file = dir.appendingPathComponent("photo.jpg")
        try writeImage(file, width: 50, height: 50, type: "public.jpeg" as CFString)
        let original = try Data(contentsOf: file)
        #expect(throws: Boom.self) {
            try ImageResizer.overwrite(file, with: Data(repeating: 7, count: 10_000)) { handle, data in
                try handle.write(contentsOf: data.prefix(100))   // half a write, then the disk "fails"
                throw Boom()
            }
        }
        #expect(try Data(contentsOf: file) == original)
    }
}

@Suite struct MetadataModeTests {
    @Test func keepAllButLocationDropsGPSOnly() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("trip.jpg")
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 30.27, kCGImagePropertyGPSLatitudeRef: "N"]
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "TestCam", kCGImagePropertyTIFFModel: "One"]
        let iptc: [CFString: Any] = [kCGImagePropertyIPTCCity: "Austin", kCGImagePropertyIPTCCaptionAbstract: "Road trip"]
        try writeImage(src, width: 200, height: 200, type: "public.jpeg" as CFString,
                       extra: [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyTIFFDictionary: tiff,
                               kCGImagePropertyIPTCDictionary: iptc])

        var o = opts(.none)
        o.metadata = .keepAllButLocation
        let out = dir.appendingPathComponent("out.jpg")
        try ImageResizer(options: o).process(source: src, destination: out)
        let props = read(out).1
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String == "TestCam")
        let outIPTC = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        #expect(outIPTC?[kCGImagePropertyIPTCCity] == nil)
        #expect(outIPTC?[kCGImagePropertyIPTCCaptionAbstract] as? String == "Road trip")
    }

    /// Writes a JPEG with XMP-only fields (keywords, rating) plus GPS and a city.
    private func writeXMPPhoto(_ url: URL) throws {
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let meta = CGImageMetadataCreateMutable()
        let dc = "http://purl.org/dc/elements/1.1/" as CFString
        let xmp = "http://ns.adobe.com/xap/1.0/" as CFString
        let ps = "http://ns.adobe.com/photoshop/1.0/" as CFString
        let subject = CGImageMetadataTagCreate(dc, "dc" as CFString, "subject" as CFString, .arrayUnordered, ["beach", "sunset"] as CFArray)!
        CGImageMetadataSetTagWithPath(meta, nil, "dc:subject" as CFString, subject)
        let rating = CGImageMetadataTagCreate(xmp, "xmp" as CFString, "Rating" as CFString, .string, "4" as CFString)!
        CGImageMetadataSetTagWithPath(meta, nil, "xmp:Rating" as CFString, rating)
        // XMP-only fields, with no IPTC/EXIF twin: a color label, Lightroom keywords, an IPTC Core location.
        let label = CGImageMetadataTagCreate(xmp, "xmp" as CFString, "Label" as CFString, .string, "Red" as CFString)!
        CGImageMetadataSetTagWithPath(meta, nil, "xmp:Label" as CFString, label)
        let lr = "http://ns.adobe.com/lightroom/1.0/" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(meta, lr, "lr" as CFString, nil)
        let hier = CGImageMetadataTagCreate(lr, "lr" as CFString, "hierarchicalSubject" as CFString, .arrayUnordered, ["Places|Beach"] as CFArray)!
        CGImageMetadataSetTagWithPath(meta, nil, "lr:hierarchicalSubject" as CFString, hier)
        let core = "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(meta, core, "Iptc4xmpCore" as CFString, nil)
        let loc = CGImageMetadataTagCreate(core, "Iptc4xmpCore" as CFString, "Location" as CFString, .string, "Zilker Park" as CFString)!
        CGImageMetadataSetTagWithPath(meta, nil, "Iptc4xmpCore:Location" as CFString, loc)
        let city = CGImageMetadataTagCreate(ps, "photoshop" as CFString, "City" as CFString, .string, "Austin" as CFString)!
        CGImageMetadataSetTagWithPath(meta, nil, "photoshop:City" as CFString, city)
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 30.27, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 97.74, kCGImagePropertyGPSLongitudeRef: "W"]
        _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitude, 30.27 as CFNumber)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImageAndMetadata(dest, ctx.makeImage()!, meta, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func xmpValue(_ url: URL, _ path: String) -> Any? {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        guard let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(meta, nil, path as CFString) else { return nil }
        return CGImageMetadataTagCopyValue(tag)
    }

    @Test func keepAllCarriesXMP() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("xmp.jpg")
        try writeXMPPhoto(src)
        #expect(xmpValue(src, "xmp:Label") != nil)   // the fixture has it
        #expect(xmpValue(src, "Iptc4xmpCore:Location") != nil)

        var o = opts(.width, w: 100)
        o.metadata = .keepAll
        let out = dir.appendingPathComponent("out.jpg")
        try ImageResizer(options: o).process(source: src, destination: out)
        #expect(xmpValue(out, "xmp:Rating") as? String == "4")
        #expect(xmpValue(out, "dc:subject") != nil)
        #expect(xmpValue(out, "xmp:Label") as? String == "Red")
        #expect(xmpValue(out, "lr:hierarchicalSubject") != nil)
        #expect(xmpValue(out, "Iptc4xmpCore:Location") as? String == "Zilker Park")
        #expect(read(out).1[kCGImagePropertyGPSDictionary] != nil)
        #expect(read(out).0.width == 100)
    }

    @Test func keepAllButLocationDropsXMPPlacesToo() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("xmp.jpg")
        try writeXMPPhoto(src)
        var o = opts(.width, w: 100)
        o.metadata = .keepAllButLocation
        let out = dir.appendingPathComponent("out.jpg")
        try ImageResizer(options: o).process(source: src, destination: out)
        #expect(xmpValue(out, "xmp:Rating") as? String == "4")
        #expect(xmpValue(out, "photoshop:City") == nil)
        #expect(xmpValue(out, "Iptc4xmpCore:Location") == nil)
        #expect(xmpValue(out, "xmp:Label") as? String == "Red")
        #expect(xmpValue(out, "lr:hierarchicalSubject") != nil)
        #expect(xmpValue(out, "exif:GPSLatitude") == nil)
        #expect(read(out).1[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func keptMetadataNeverRotatesAgain() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("rotated.jpg")
        try writeImage(src, width: 400, height: 300, type: "public.jpeg" as CFString, orientation: 6,
                       extra: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6, kCGImagePropertyTIFFMake: "Cam"]])
        var o = opts(.none)
        o.metadata = .keepAll
        let out = dir.appendingPathComponent("out.jpg")
        try ImageResizer(options: o).process(source: src, destination: out)
        let (img, props) = read(out)
        #expect(img.width == 300 && img.height == 400)
        #expect((props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 == 1)
        #expect(xmpValue(out, "tiff:Orientation").map { "\($0)" } ?? "1" == "1")
    }

    @Test func removeAllDropsXMP() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("xmp.jpg")
        try writeXMPPhoto(src)
        let out = dir.appendingPathComponent("out.jpg")
        try ImageResizer(options: opts(.width, w: 100)).process(source: src, destination: out)
        #expect(xmpValue(out, "xmp:Rating") == nil)
        #expect(xmpValue(out, "dc:subject") == nil)
        #expect(xmpValue(out, "xmp:Label") == nil)
    }

    @Test func oldYesNoSettingStillLoads() throws {
        let kept = try JSONDecoder().decode(ResizeOptions.self, from: #"{"copyMetadata":true}"#.data(using: .utf8)!)
        #expect(kept.metadata == .keepAll)
        let stripped = try JSONDecoder().decode(ResizeOptions.self, from: #"{"copyMetadata":false}"#.data(using: .utf8)!)
        #expect(stripped.metadata == .removeAll)
        #expect(try JSONDecoder().decode(ResizeOptions.self, from: Data("{}".utf8)).metadata == .removeAll)
    }
}

@Suite struct BesideOriginalsTests {
    @Test func resultsLandNextToEachOriginalWithSuffix() throws {
        let root = try tempDir()
        let album = root.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: album.appendingPathComponent("Day 2"), withIntermediateDirectories: true)
        try writeImage(album.appendingPathComponent("a.png"), width: 10, height: 10, type: "public.png" as CFString)
        try writeImage(album.appendingPathComponent("Day 2/b.jpg"), width: 10, height: 10, type: "public.jpeg" as CFString)
        try Data("notes".utf8).write(to: album.appendingPathComponent("notes.txt"))
        // A result from an earlier run must not be resized again.
        try writeImage(album.appendingPathComponent("a-1200.jpg"), width: 10, height: 10, type: "public.jpeg" as CFString)

        let jobs = BatchJobs.collect(from: [album], placement: .besideOriginals, format: .jpeg,
                                     suffix: "-1200", copyNonImageFiles: true)
        let pairs = Set(jobs.map { "\($0.source.lastPathComponent) -> \($0.destination.path.components(separatedBy: "/Album/").last!)" })
        #expect(pairs == ["a.png -> a-1200.jpg", "b.jpg -> Day 2/b-1200.jpg"])
        #expect(jobs.allSatisfy { $0.kind == .resize })
    }

    @Test func suffixAlsoAppliesInFolderMode() throws {
        let root = try tempDir()
        let src = root.appendingPathComponent("photo.heic")
        try writeImage(src, width: 10, height: 10, type: "public.jpeg" as CFString)
        let jobs = BatchJobs.collect(from: [src], placement: .folder(URL(fileURLWithPath: "/tmp/out")),
                                     format: .jpeg, suffix: "-web", copyNonImageFiles: true)
        #expect(jobs.map(\.destination.path) == ["/tmp/out/photo-web.jpg"])
    }

    @Test func besideOriginalsNeedsASuffix() {
        var o = ResizeOptions()
        o.saveBesideOriginals = true
        #expect(o.validationError != nil)
        o.fileSuffix = " / "
        #expect(o.validationError != nil)
        o.fileSuffix = "-1200"
        #expect(o.validationError == nil)
    }
}
