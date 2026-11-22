import simd

/// Where the live sky camera was pointing when the constellation was captured.
/// World space is the sky's: +x east, +y up, -z true north (see `Astronomy.arDirection`).
nonisolated struct SkyCameraPose: Sendable {
    /// The camera's orientation; it looks along its local -z.
    let orientation: simd_quatf
    /// Vertical field of view of the preview on screen, in degrees.
    let verticalFieldOfViewDegrees: Double
}
