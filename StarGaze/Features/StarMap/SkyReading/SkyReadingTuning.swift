import Foundation

/// Every number behind the sky photo and (later) the light-pollution estimate, in one place.
/// These are settings for a handheld phone camera, so the results are estimates, not calibrated
/// measurements.
nonisolated enum SkyReadingTuning {
    // MARK: Countdown

    /// "Hold still… 3·2·1" before the shot.
    static let countdownSeconds = 3
    /// Wait after pausing ARKit so it has released the camera before AVFoundation takes it.
    static let arReleaseDelay: Duration = .milliseconds(300)

    // MARK: Camera

    /// Longest exposure we ask for. If the camera format allows less, we use the format's maximum.
    static let targetExposureSeconds: Double = 1.0
    /// ISO as a fraction of the format's maximum. The very top is mostly amplified noise.
    static let isoFraction: Float = 0.8
    /// Lens position for "infinity". 1.0 is the far end of the focus range, which is close to
    /// (but not exactly) infinity on every iPhone.
    static let focusLensPosition: Float = 1.0
    /// White balance is locked so photos are comparable with each other (Kelvin).
    static let whiteBalanceTemperature: Float = 4000
    /// Keep the full photo at or under this many pixels (memory: 4 bytes per pixel).
    static let maxPhotoPixels = 12_500_000
    /// Extra frames to wait after the custom exposure is applied, so the sensor has settled.
    static let settleFrames = 1
    /// Give up if the photo hasn't arrived in this time (the find is already collected).
    static let captureTimeoutSeconds: Double = 8

    // MARK: Star detection (on the downscaled, linear-luminance photo)

    /// Longest side of the image the detector works on. Downscaling averages noise and keeps
    /// detection well under a second.
    static let detectionMaxDimension = 2000
    /// Background is the median of square cells this many pixels wide, smoothed and interpolated.
    static let backgroundCellSize = 32
    /// A star's peak must be at least this many noise sigmas above the background.
    static let peakSigma: Float = 5
    /// Pixels belonging to a star must be at least this many sigmas above the background.
    static let supportSigma: Float = 2.5
    /// Fewer supporting pixels than this is a hot pixel or a noise spike, not a star.
    static let minStarPixels = 3
    /// More supporting pixels than this is a light, a building or the Moon, not a star.
    static let maxStarPixels = 60
    /// Peak more than this many times its brightest direct neighbour: a single hot pixel.
    static let maxPeakToNeighbor: Float = 4
    /// Blobs with at least `elongationMinPixels` pixels longer than this ratio are edges or wires.
    static let maxElongation: Float = 3
    static let elongationMinPixels = 6
    /// Linear value treated as clipped.
    static let saturationLevel: Float = 0.98
    /// More clipped pixels than this in one blob is a light source, not a star.
    static let maxSaturatedPixels = 6
    /// Stars this close to the image edge (pixels) are ignored.
    static let edgeMargin = 8

    // MARK: Motion

    /// Device-motion sample rate while shooting.
    static let motionUpdateInterval: TimeInterval = 1.0 / 100.0

    // MARK: Debug

    /// How long the DEBUG exposure summary stays on screen.
    static let debugSummaryDuration: Duration = .seconds(8)
}
