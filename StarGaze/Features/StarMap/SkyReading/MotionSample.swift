/// One Core Motion reading while the photo is being taken.
nonisolated struct MotionSample: Sendable {
    /// Seconds since boot (same clock as `ProcessInfo.systemUptime`).
    let timestamp: Double
    /// Magnitude of the rotation rate, radians per second.
    let rotationRate: Double
    /// Gravity in device coordinates (g).
    let gravity: SIMD3<Double>
}
