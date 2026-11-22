/// One point-like source the detector accepted as a star.
nonisolated struct DetectedStar: Sendable, Equatable {
    /// Flux-weighted centroid, in pixels of the detector's working image.
    let x: Float
    let y: Float
    /// Sum of background-subtracted light over the star's pixels.
    let flux: Float
    /// Brightest background-subtracted pixel.
    let peak: Float
    let pixelCount: Int
}
