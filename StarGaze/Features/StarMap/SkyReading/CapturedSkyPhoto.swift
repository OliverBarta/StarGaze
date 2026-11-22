import CoreGraphics

/// The still photo straight from AVFoundation, plus what the camera actually did.
/// The image is in the sensor's native landscape orientation.
/// Pixels are processed and gamma-encoded by the phone, not linear sensor values.
nonisolated struct CapturedSkyPhoto: @unchecked Sendable {
    let image: CGImage
    let exposureSeconds: Double
    let iso: Double
    let lensPosition: Float
    /// Horizontal field of view of the camera format, degrees (for the sensor's long side).
    let fieldOfViewDegrees: Float
    /// When the shutter opened and closed, seconds since boot.
    let exposureStart: Double
    let exposureEnd: Double
}
