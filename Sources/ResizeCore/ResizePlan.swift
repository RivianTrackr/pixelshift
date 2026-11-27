import CoreGraphics

/// What to take from the source (crop, in top-left pixel coordinates of the
/// upright image) and how big the output is.
public struct ResizePlan: Equatable, Sendable {
    public var crop: CGRect
    public var outputWidth: Int
    public var outputHeight: Int

    public init(crop: CGRect, outputWidth: Int, outputHeight: Int) {
        self.crop = crop
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
    }

    public static func make(sourceWidth: Int, sourceHeight: Int, options o: ResizeOptions) -> ResizePlan {
        let w = Double(max(sourceWidth, 1))
        let h = Double(max(sourceHeight, 1))
        let tw = Double(max(o.width, 1))
        let th = Double(max(o.height, 1))
        var crop = CGRect(x: 0, y: 0, width: w, height: h)
        var outW: Double
        var outH: Double

        switch o.method {
        case .none:
            outW = w; outH = h
        case .percent:
            let p = max(o.percent, 0.0001) / 100
            outW = w * p; outH = h * p
        case .width:
            outW = tw; outH = h * tw / w
        case .height:
            outH = th; outW = w * th / h
        case .fit:
            let s = min(tw / w, th / h)
            outW = w * s; outH = h * s
        case .crop, .cropThenFit:
            let ratio = tw / th
            if w / h > ratio {
                let cw = min(w, max(1, (h * ratio).rounded()))
                crop = CGRect(x: ((w - cw) / 2).rounded(.down), y: 0, width: cw, height: h)
            } else {
                let ch = min(h, max(1, (w / ratio).rounded()))
                crop = CGRect(x: 0, y: ((h - ch) / 2).rounded(.down), width: w, height: ch)
            }
            if o.method == .crop {
                outW = crop.width; outH = crop.height
            } else {
                outW = tw; outH = th
            }
        }

        if o.scaleDownOnly && (outW > crop.width || outH > crop.height) {
            outW = crop.width
            outH = crop.height
        }

        return ResizePlan(
            crop: crop,
            outputWidth: max(1, Int(outW.rounded())),
            outputHeight: max(1, Int(outH.rounded()))
        )
    }

    /// The same plan for a decoded image of a different size than the one planned
    /// for (a reduced-size decode), so the crop lands on the same part of the picture.
    func scaled(toWidth dw: Int, height dh: Int, from w: Int, _ h: Int) -> ResizePlan {
        guard dw != w || dh != h else { return self }
        let sx = Double(dw) / Double(w), sy = Double(dh) / Double(h)
        var c = CGRect(x: (crop.minX * sx).rounded(), y: (crop.minY * sy).rounded(),
                       width: (crop.width * sx).rounded(), height: (crop.height * sy).rounded())
        c = c.intersection(CGRect(x: 0, y: 0, width: dw, height: dh))
        return ResizePlan(crop: c, outputWidth: outputWidth, outputHeight: outputHeight)
    }
}
