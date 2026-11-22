import Accelerate
import CoreGraphics

/// A single-channel, linear-light (not gamma-encoded) float image, row-major, values 0...1.
/// Made from the phone's processed photo, so "linear" is only as good as iOS's tone mapping.
nonisolated struct LuminanceImage: Sendable {
    let width: Int
    let height: Int
    var pixels: [Float]

    init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Converts to linear gray with vImage, then halves with `binnedRejectingHotPixels` until the
    /// long side is under 1.5 × `maxDimension`. There's no resampling (it would ring around bright
    /// edges and make fake stars), so the result can be up to 1.5 × `maxDimension`.
    init?(cgImage: CGImage, maxDimension: Int) {
        guard let linearGray = CGColorSpace(name: CGColorSpace.linearGray),
              let format = vImage_CGImageFormat(
                  bitsPerComponent: 32, bitsPerPixel: 32, colorSpace: linearGray,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue
                      | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)),
              let full = try? vImage_Buffer(cgImage: cgImage, format: format) else { return nil }
        defer { full.free() }

        var image = LuminanceImage(buffer: full)
        while max(image.width, image.height) >= maxDimension * 3 / 2 {
            image = image.binnedRejectingHotPixels()
        }
        self = image
    }

    private init(buffer: vImage_Buffer) {
        let width = Int(buffer.width), height = Int(buffer.height)
        var pixels = [Float](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let row = buffer.data.advanced(by: y * buffer.rowBytes).assumingMemoryBound(to: Float.self)
                out.baseAddress!.advanced(by: y * width).update(from: row, count: width)
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Half size, each output pixel the SECOND brightest of its 2×2 block. A single hot pixel
    /// disappears; a real star (spread over several pixels by optics and seeing) survives.
    func binnedRejectingHotPixels() -> LuminanceImage {
        let w = width / 2, h = height / 2
        var out = [Float](repeating: 0, count: w * h)
        var hiTop = [Float](repeating: 0, count: w), loTop = hiTop, hiBottom = hiTop, loBottom = hiTop
        let n = vDSP_Length(w)
        pixels.withUnsafeBufferPointer { px in
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<h {
                    let top = px.baseAddress! + (2 * y) * width
                    let bottom = top + width
                    // pairs (a, b) from the top row and (c, d) from the bottom row
                    vDSP_vmax(top, 2, top + 1, 2, &hiTop, 1, n)
                    vDSP_vmin(top, 2, top + 1, 2, &loTop, 1, n)
                    vDSP_vmax(bottom, 2, bottom + 1, 2, &hiBottom, 1, n)
                    vDSP_vmin(bottom, 2, bottom + 1, 2, &loBottom, 1, n)
                    // second largest = max(min(hiTop, hiBottom), max(loTop, loBottom))
                    vDSP_vmin(hiTop, 1, hiBottom, 1, &hiTop, 1, n)
                    vDSP_vmax(loTop, 1, loBottom, 1, &loTop, 1, n)
                    vDSP_vmax(hiTop, 1, loTop, 1, o.baseAddress! + y * w, 1, n)
                }
            }
        }
        return LuminanceImage(width: w, height: h, pixels: out)
    }
}
