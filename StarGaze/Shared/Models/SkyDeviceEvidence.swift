//
//  SkyDeviceEvidence.swift
//  StarGaze
//

import Foundation

/// What the phone itself measured during a live sky photo. For live captures this outranks
/// Gemini on "is this the sky?" and "is it blurred?". Library photos have none.
nonisolated struct SkyDeviceEvidence: Equatable, Sendable {
    /// Angle of the camera's view above the horizon, from gravity at the shutter (nil if unknown).
    var cameraElevationDegrees: Double?
    /// Fastest rotation while the shutter was open (nil if motion wasn't recorded).
    var maxRotationDegreesPerSecond: Double?
    /// Stars the detector kept, and blobs it rejected as streaks (nil if detection didn't run).
    var detectedStars: Int?
    var elongatedRejections: Int?

    /// Camera elevation from gravity in device coordinates. The back camera looks along −z, so
    /// its elevation is asin(gravity.z): +90° with the screen facing straight down.
    static func cameraElevationDegrees(gravity: (x: Double, y: Double, z: Double)) -> Double? {
        let length = (gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z).squareRoot()
        guard length > 0.1 else { return nil }
        return asin(max(-1, min(1, gravity.z / length))) * 180 / .pi
    }

    /// The camera was aimed upward, at the sky rather than a wall, the ground or a screen in front.
    var pointedAtSky: Bool {
        guard let cameraElevationDegrees else { return false }
        return cameraElevationDegrees >= SkyReadingTuning.minSkyElevationDegrees
    }

    /// The phone turned too fast during the exposure (nil if unknown).
    var moved: Bool? {
        maxRotationDegreesPerSecond.map { $0 > SkyReadingTuning.maxSteadyRotationDegreesPerSecond }
    }

    /// The detector saw mostly streaks instead of points (nil if detection didn't run).
    var streaked: Bool? {
        guard let detectedStars, let elongatedRejections else { return nil }
        let blobs = detectedStars + elongatedRejections
        return elongatedRejections >= SkyReadingTuning.minStreaksForBlur
            && Double(elongatedRejections) >= SkyReadingTuning.streakFractionForBlur * Double(blobs)
    }
}
