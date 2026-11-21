import Foundation

/// Everything known before the sky photo is taken.
nonisolated struct SkyShotContext: Sendable {
    let constellationID: String
    let constellationName: String
    /// Full precision, kept in memory only; saved readings round it to ~1 km.
    let latitude: Double
    let longitude: Double
    let takenAt: Date
    let arCamera: ARCameraSnapshot
}
