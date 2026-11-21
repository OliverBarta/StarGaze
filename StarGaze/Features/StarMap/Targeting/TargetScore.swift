/// How well the view direction matches one constellation. Lower is better.
nonisolated struct TargetScore: Equatable, Sendable {
    /// Angle to the nearest star or line, or 0 inside the figure's outline.
    let distance: Float
    /// Angle to the centre divided by the figure's angular radius. Breaks ties when
    /// several outlines contain the view, so a small figure inside a big one can still win.
    let centerRatio: Float

    /// Plain ordering, used to pick the best candidate.
    func isBetter(than other: TargetScore) -> Bool {
        distance != other.distance ? distance < other.distance : centerRatio < other.centerRatio
    }

    /// Better by a clear margin (`ratio` < 1), used for hysteresis.
    func isClearlyBetter(than other: TargetScore, ratio: Float) -> Bool {
        if distance == 0, other.distance == 0 {
            return centerRatio < other.centerRatio * ratio
        }
        return distance < other.distance * ratio
    }
}
