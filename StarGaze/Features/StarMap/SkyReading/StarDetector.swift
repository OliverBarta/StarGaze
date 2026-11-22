import Accelerate

/// Finds stars in a sky photo. Pure: works on a `LuminanceImage`, no camera or UI.
///
/// 1. Background: median of square cells, smoothed with a 3×3 median, bilinearly interpolated.
/// 2. Noise: 1.4826 × median absolute deviation of the background-subtracted image.
/// 3. Candidates: local maxima more than `peakSigma` above the background.
/// 4. Each candidate grows over neighbours above `supportSigma` and must look like a star:
///    a few pixels (not one hot pixel), not huge, not clipped, not a line, not at the edge.
nonisolated enum StarDetector {
    typealias Tuning = SkyReadingTuning

    static func detect(in image: LuminanceImage, exposureSeconds: Double, iso: Double) -> StarDetectionResult {
        let (background, backgroundMedian) = background(of: image)
        var residual = [Float](repeating: 0, count: image.pixels.count)
        vDSP_vsub(background, 1, image.pixels, 1, &residual, 1, vDSP_Length(residual.count))
        let sigma = max(robustSigma(residual), 1e-6)
        let (stars, rejections) = findStars(in: image, residual: residual, sigma: sigma)
        let exposureISO = max(exposureSeconds * iso / 100, 1e-6)
        return StarDetectionResult(
            stars: stars, rejections: rejections, backgroundMedian: backgroundMedian, noiseSigma: sigma,
            relativeSkyGlow: Double(backgroundMedian) / exposureISO,
            imageWidth: image.width, imageHeight: image.height)
    }

    // MARK: - Background

    /// Smooth background per pixel, and the median of all cell medians.
    static func background(of image: LuminanceImage) -> (pixels: [Float], median: Float) {
        let cell = Tuning.backgroundCellSize
        let columns = (image.width + cell - 1) / cell
        let rows = (image.height + cell - 1) / cell
        var grid = [Float](repeating: 0, count: columns * rows)
        var scratch = [Float]()
        scratch.reserveCapacity(cell * cell)

        image.pixels.withUnsafeBufferPointer { px in
            for gy in 0..<rows {
                for gx in 0..<columns {
                    scratch.removeAll(keepingCapacity: true)
                    let x1 = min(image.width, (gx + 1) * cell)
                    for y in (gy * cell)..<min(image.height, (gy + 1) * cell) {
                        let row = y * image.width
                        scratch.append(contentsOf: px[(row + gx * cell)..<(row + x1)])
                    }
                    grid[gy * columns + gx] = median(&scratch)
                }
            }
        }
        grid = medianFilter3x3(grid, columns: columns, rows: rows)
        var all = grid
        let overall = median(&all)
        return (interpolate(grid, columns: columns, rows: rows, cell: cell, width: image.width, height: image.height),
                overall)
    }

    private static func medianFilter3x3(_ grid: [Float], columns: Int, rows: Int) -> [Float] {
        var out = grid
        var window = [Float]()
        for y in 0..<rows {
            for x in 0..<columns {
                window.removeAll(keepingCapacity: true)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, nx < columns, ny >= 0, ny < rows { window.append(grid[ny * columns + nx]) }
                    }
                }
                out[y * columns + x] = median(&window)
            }
        }
        return out
    }

    /// Bilinear interpolation between cell centres.
    private static func interpolate(_ grid: [Float], columns: Int, rows: Int, cell: Int,
                                    width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        let half = Float(cell) / 2
        out.withUnsafeMutableBufferPointer { o in
            grid.withUnsafeBufferPointer { g in
                for y in 0..<height {
                    let fy = min(max((Float(y) - half) / Float(cell), 0), Float(rows - 1))
                    let y0 = Int(fy), y1 = min(y0 + 1, rows - 1)
                    let ty = fy - Float(y0)
                    for x in 0..<width {
                        let fx = min(max((Float(x) - half) / Float(cell), 0), Float(columns - 1))
                        let x0 = Int(fx), x1 = min(x0 + 1, columns - 1)
                        let tx = fx - Float(x0)
                        let top = g[y0 * columns + x0] * (1 - tx) + g[y0 * columns + x1] * tx
                        let bottom = g[y1 * columns + x0] * (1 - tx) + g[y1 * columns + x1] * tx
                        o[y * width + x] = top * (1 - ty) + bottom * ty
                    }
                }
            }
        }
        return out
    }

    // MARK: - Noise

    /// 1.4826 × MAD, from every 4th pixel (plenty for a stable estimate).
    static func robustSigma(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var sample = Swift.stride(from: 0, to: values.count, by: 4).map { values[$0] }
        let center = median(&sample)
        var deviations = sample
        var negative = -center
        vDSP_vsadd(sample, 1, &negative, &deviations, 1, vDSP_Length(sample.count))
        vDSP_vabs(deviations, 1, &deviations, 1, vDSP_Length(deviations.count))
        return 1.4826 * median(&deviations)
    }

    /// Median using vDSP's sort (sorts `values` in place).
    static func median(_ values: inout [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        vDSP_vsort(&values, vDSP_Length(values.count), 1)
        let mid = values.count / 2
        return values.count % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2
    }

    // MARK: - Stars

    private static func findStars(in image: LuminanceImage, residual: [Float],
                                  sigma: Float) -> ([DetectedStar], StarRejections) {
        let width = image.width, height = image.height
        let margin = Tuning.edgeMargin
        guard width > 2 * margin + 2, height > 2 * margin + 2 else { return ([], StarRejections()) }
        let peakLevel = Tuning.peakSigma * sigma
        let supportLevel = Tuning.supportSigma * sigma
        var visited = [Bool](repeating: false, count: width * height)
        var stars: [DetectedStar] = []
        var rejections = StarRejections()
        var stack: [Int] = []

        residual.withUnsafeBufferPointer { r in
            image.pixels.withUnsafeBufferPointer { raw in
                for y in 1..<(height - 1) {
                    for x in 1..<(width - 1) {
                        let i = y * width + x
                        let v = r[i]
                        guard v > peakLevel, !visited[i] else { continue }
                        // local maximum (ties go to the first pixel in scan order)
                        guard v > r[i - width - 1], v > r[i - width], v > r[i - width + 1], v > r[i - 1],
                              v >= r[i + 1], v >= r[i + width - 1], v >= r[i + width], v >= r[i + width + 1]
                        else { continue }

                        // grow over supporting pixels
                        var count = 0, saturated = 0
                        var flux: Float = 0, sx: Float = 0, sy: Float = 0
                        var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
                        var touchesEdge = false
                        func grow(_ n: Int) {
                            guard !visited[n], r[n] > supportLevel else { return }
                            visited[n] = true
                            stack.append(n)
                        }
                        stack.removeAll(keepingCapacity: true)
                        stack.append(i)
                        visited[i] = true
                        while let p = stack.popLast() {
                            let px = p % width, py = p / width
                            // moments relative to the peak pixel: absolute coordinates squared
                            // (~10⁶) would swamp a star's sub-pixel spread in Float precision
                            let dx = Float(px - x), dy = Float(py - y)
                            let w = r[p]
                            count += 1
                            flux += w
                            sx += w * dx
                            sy += w * dy
                            sxx += w * dx * dx
                            syy += w * dy * dy
                            sxy += w * dx * dy
                            if raw[p] >= Tuning.saturationLevel { saturated += 1 }
                            if px < margin || py < margin || px >= width - margin || py >= height - margin {
                                touchesEdge = true
                            }
                            if px > 0 { grow(p - 1) }
                            if px < width - 1 { grow(p + 1) }
                            if py > 0 { grow(p - width) }
                            if py < height - 1 { grow(p + width) }
                        }

                        let neighbor = max(r[i - 1], r[i + 1], r[i - width], r[i + width], 1e-9)
                        if count < Tuning.minStarPixels || v / neighbor > Tuning.maxPeakToNeighbor {
                            rejections.hotPixels += 1
                        } else if count > Tuning.maxStarPixels {
                            rejections.tooLarge += 1
                        } else if saturated > Tuning.maxSaturatedPixels {
                            rejections.saturated += 1
                        } else if touchesEdge {
                            rejections.atEdge += 1
                        } else if count >= Tuning.elongationMinPixels,
                                  elongation(flux: flux, sx: sx, sy: sy, sxx: sxx, syy: syy, sxy: sxy)
                                    > Tuning.maxElongation {
                            rejections.elongated += 1
                        } else {
                            stars.append(DetectedStar(x: Float(x) + sx / flux, y: Float(y) + sy / flux, flux: flux,
                                                      peak: v, pixelCount: count))
                        }
                    }
                }
            }
        }
        stars.sort { $0.flux > $1.flux }
        return (stars, rejections)
    }

    /// Ratio of the long to the short axis from the weighted second moments (1 = round).
    /// Sums must be relative to a point inside the blob (the peak), not absolute coordinates.
    static func elongation(flux: Float, sx: Float, sy: Float, sxx: Float, syy: Float, sxy: Float) -> Float {
        let mx = sx / flux, my = sy / flux
        let a = sxx / flux - mx * mx
        let b = syy / flux - my * my
        let c = sxy / flux - mx * my
        let spread = ((a - b) * (a - b) / 4 + c * c).squareRoot()
        let major = (a + b) / 2 + spread
        let minor = max((a + b) / 2 - spread, 1e-6)
        return (major / minor).squareRoot()
    }
}
