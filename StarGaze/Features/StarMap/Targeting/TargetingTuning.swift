import Foundation

/// Every knob for aiming at and collecting constellations, in one place.
/// Angles are in radians; write them as `degrees * .pi / 180`.
nonisolated enum TargetingTuning {
    /// How far outside its figure you can aim and still target a constellation.
    /// Small figures get `minTolerance`, large ones `maxTolerance`, linear in between.
    static let minTolerance: Float = 3 * .pi / 180
    static let maxTolerance: Float = 8 * .pi / 180
    /// Angular radius (centre to farthest star) at which the tolerance is smallest / largest.
    static let smallFigureRadius: Float = 5 * .pi / 180
    static let largeFigureRadius: Float = 25 * .pi / 180

    /// Constellations whose centre is lower than this (degrees) can't be targeted.
    static let minAltitude: Double = -5

    /// A challenger must score below `switchRatio` × the current target's score
    /// for `switchHold` seconds in a row before the target changes.
    static let switchRatio: Float = 0.7
    static let switchHold: Double = 0.3

    /// Seconds of steady aim needed to collect.
    static let dwellNeeded: Double = 1.5
    /// Progress drains this many times faster than it fills while the target is lost.
    static let decayRate: Double = 2

    /// Opacity multiplier for everything except the target while something is targeted.
    static let dimFactor: CGFloat = 0.6
    /// How quickly highlight opacities ease toward their goal (per second).
    static let highlightSpeed: CGFloat = 10
}
