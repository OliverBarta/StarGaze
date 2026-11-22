import Foundation

/// Every number behind the sky photo and (later) the light-pollution estimate, in one place.
/// These are settings for a handheld phone camera, so the results are estimates, not calibrated
/// measurements.
nonisolated enum SkyReadingTuning {
    // MARK: Countdown

    /// "Hold still… 3·2·1" before the shot.
    static let countdownSeconds = 3
    /// Extra wait after the live preview has stopped, before the photo session takes the camera.
    static let cameraReleaseDelay: Duration = .milliseconds(150)

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

    // MARK: Gemini

    /// How many of the target's brightest stars are named in Gemini's prompt.
    static let contextStarCount = 6
    /// Give up on Gemini after this long; the reading then has no quality check.
    static let geminiTimeoutSeconds: TimeInterval = 20

    // MARK: Estimate

    /// Detected stars → Bortle class, brightest sky first match wins from the top.
    /// Rough bands for a ~1 s handheld exposure; a phone can't tell Bortle 1–2 apart from 3.
    /// TODO(Part 5): replace with detected vs. expected catalog stars.
    static let bortleForStarCount: [(minStars: Int, bortle: Int)] = [
        (150, 3), (80, 4), (40, 5), (20, 6), (10, 7), (4, 8),
    ]
    /// Gemini's brightness guess lowers confidence when it's this many classes away.
    static let geminiDisagreementClasses = 2
    /// Sun higher than this (degrees): "Twilight", unreliable.
    static let maxSunAltitudeDegrees = -12.0
    /// Moon above the horizon and more lit than this: kept, but low confidence.
    static let brightMoonIllumination = 0.5

    // MARK: Device evidence

    /// The capture button needs the camera at least this far above the horizon ("Point up at the sky").
    static let minCaptureElevationDegrees = 15.0
    /// Hysteresis so the button doesn't flicker right at the threshold.
    static let captureElevationHysteresisDegrees = 2.0

    /// Camera at least this far above the horizon counts as aimed at the sky, so Gemini's
    /// "not a sky photo" needs high confidence to count.
    static let minSkyElevationDegrees = 20.0
    /// Peak rotation above this during the exposure: "Phone moved". A first guess; tune outdoors
    /// (handheld peaks are often 1–2°/s, and the detector's streak check catches real smearing).
    static let maxSteadyRotationDegreesPerSecond = 3.0
    /// The detector saw streaks if at least this many blobs were rejected as elongated…
    static let minStreaksForBlur = 5
    /// …and they were at least this share of all star-like blobs.
    static let streakFractionForBlur = 0.5

    // MARK: Motion

    /// Device-motion sample rate while shooting.
    static let motionUpdateInterval: TimeInterval = 1.0 / 100.0

    // MARK: Toasts

    /// How long each capture toast stays on screen.
    static let toastDuration: Duration = .seconds(3)
}
