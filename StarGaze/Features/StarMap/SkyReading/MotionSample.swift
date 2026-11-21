import simd

/// One Core Motion reading while the photo is being taken.
nonisolated struct MotionSample: Sendable {
    /// Seconds since boot (same clock as `ProcessInfo.systemUptime`).
    let timestamp: Double
    /// Device attitude in the `referenceFrame` of the recording.
    let attitude: simd_quatd
    /// Magnitude of the rotation rate, radians per second.
    let rotationRate: Double
    /// Gravity in device coordinates (g).
    let gravity: SIMD3<Double>
}
