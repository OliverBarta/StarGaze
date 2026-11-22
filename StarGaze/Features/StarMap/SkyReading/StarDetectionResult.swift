/// What the on-device detector found in one sky photo.
nonisolated struct StarDetectionResult: Sendable, Equatable {
    /// Brightest first.
    let stars: [DetectedStar]
    let rejections: StarRejections
    /// Median background in linear units (0...1), before normalizing.
    let backgroundMedian: Float
    /// Robust noise estimate (1.4826 × median absolute deviation) of the background-subtracted image.
    let noiseSigma: Float
    /// Background per second per ISO 100. Comparable between photos from the same phone model,
    /// not across models, and not a calibrated sky brightness.
    let relativeSkyGlow: Double
    let imageWidth: Int
    let imageHeight: Int

    var starCount: Int { stars.count }
}
