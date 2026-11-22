import Foundation

/// One saved light-pollution reading from a sky photo. An estimate from a handheld phone camera,
/// not a calibrated measurement. Saved on the device as snake_case JSON (see `SkyReadingStore`).
nonisolated struct SkyPhotoReading: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var takenAt: Date
    var constellationID: String
    var constellationName: String
    /// Rounded to 2 decimals (about 1 km).
    var latitude: Double
    var longitude: Double
    /// False when the phone had no location fix (the coordinates are the fallback city).
    var hasLocation: Bool
    var source: SkyReadingSource
    var deviceModel: String
    var exposureSeconds: Double
    var iso: Double
    var detectedStars: Int?
    /// Filled in once the deeper star catalog is used (Part 5).
    var expectedStars: Int?
    var limitingMagnitude: Double?
    var relativeSkyGlow: Double?
    var bortle: Int
    var band: SkyBand
    var confidence: SkyConfidence
    /// Counts toward the light-pollution map.
    var reliable: Bool
    var issues: [SkyReadingIssue]
    var method = "count+gemini"
    var gemini: SkyAnalysis?
    var level: FindLevel
    /// Camera elevation at the shutter, from gravity (nil if motion wasn't recorded).
    var cameraElevationDegrees: Double?
    /// Set on readings saved by older builds that photographed in demo mode; they never go on the map.
    /// (Demo mode no longer takes a photo, so new readings never set it.)
    var demoMode: Bool?
    var uploaded = false

    /// `light_readings.strength`: 0 = darkest, 1 = brightest.
    var strength: Double { Double(bortle - 1) / 8 }

    /// Waiting to be inserted into `light_readings`.
    var needsUpload: Bool { reliable && hasLocation && source == .camera && demoMode != true && !uploaded }

    /// Gemini is sure this isn't the sky.
    var isConfidentlyNotSky: Bool { issues.contains(.notSky) && gemini?.confidence == .high }

    /// The phone was lowered below the sky during the shot.
    var wasAimedTooLow: Bool {
        guard let cameraElevationDegrees else { return false }
        return cameraElevationDegrees < SkyReadingTuning.minCaptureElevationDegrees
    }

    /// The issues that made it unreliable, for the capture toast.
    var blockingIssues: [SkyReadingIssue] { issues.filter(\.isBlocking) }
}
