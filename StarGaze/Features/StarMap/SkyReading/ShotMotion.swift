import simd

/// How the phone was held while the shutter was open.
nonisolated struct ShotMotion: Sendable, Equatable {
    /// Attitude when the exposure started, in `xTrueNorthZVertical` when available.
    let attitude: simd_quatd
    /// Whether `attitude` is relative to true north (false: arbitrary heading, still gravity-aligned).
    let isTrueNorth: Bool
    /// Gravity in device coordinates when the exposure started, used for photo orientation.
    let gravity: SIMD3<Double>
    /// Fastest rotation during the exposure, degrees per second (a blur indicator).
    let maxRotationDegreesPerSecond: Double

    /// Summarizes the samples that fall within the exposure (with a small margin so a short
    /// exposure still catches at least one sample). Nil if there are none.
    static func summarize(_ samples: [MotionSample], from start: Double, to end: Double,
                          isTrueNorth: Bool, margin: Double = 0.02) -> ShotMotion? {
        let window = samples.filter { $0.timestamp >= start - margin && $0.timestamp <= end + margin }
        guard let first = window.min(by: { abs($0.timestamp - start) < abs($1.timestamp - start) }) else {
            return nil
        }
        let maxRate = window.map(\.rotationRate).max() ?? 0
        return ShotMotion(attitude: first.attitude, isTrueNorth: isTrueNorth, gravity: first.gravity,
                          maxRotationDegreesPerSecond: maxRate * 180 / .pi)
    }
}
