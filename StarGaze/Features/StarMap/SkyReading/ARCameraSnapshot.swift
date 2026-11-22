import CoreGraphics
import simd

/// Where ARKit thought the camera was pointing when the constellation was captured.
/// World space is `gravityAndHeading`: -z is true north, +y is up.
/// The intrinsics are for ARKit's video frames (sensor landscape orientation), not the still photo.
nonisolated struct ARCameraSnapshot: Sendable {
    let transform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
}
