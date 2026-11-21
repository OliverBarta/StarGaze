/// What the sky view reports about the constellation being aimed at.
struct SkyTarget: Equatable {
    let name: String
    /// Dwell progress, 0...1.
    let progress: Double
    /// Already in the collection: show the name, no progress.
    let isCollected: Bool
}
