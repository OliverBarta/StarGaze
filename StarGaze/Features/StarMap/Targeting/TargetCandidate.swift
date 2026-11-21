/// A constellation within reach of the view direction this frame.
nonisolated struct TargetCandidate: Equatable, Sendable {
    let id: String
    let score: TargetScore
    /// False for constellations already discovered: they can be targeted but not collected.
    let isCollectible: Bool
}
