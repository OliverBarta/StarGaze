import Foundation

/// Everything known before the sky photo is taken.
nonisolated struct SkyShotContext: Sendable {
    let constellationID: String
    let constellationName: String
    /// Full precision, kept in memory only; saved readings round it to ~1 km.
    let latitude: Double
    let longitude: Double
    /// False when the location is the fallback city, so the reading can't go on the map.
    let hasLocation: Bool
    let takenAt: Date
    let cameraPose: SkyCameraPose
}
