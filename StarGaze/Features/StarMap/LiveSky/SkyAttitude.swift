import simd

/// Turns CoreMotion's attitude into the SceneKit camera's orientation in the sky's world
/// (+x east, +y up, -z true north; see `Astronomy.arDirection`). Pure math, no CoreMotion types.
///
/// CoreMotion's `.xTrueNorthZVertical` reference frame is x = north, y = west, z = up.
/// `CMAttitude.rotationMatrix` maps reference-frame vectors into device coordinates
/// (x = right edge, y = top edge, z = out of the screen; the back camera looks along -z), so
/// device → world is `referenceToWorld · Rᵀ`. The screen rotation then maps the SceneKit camera's
/// axes (x = screen right, y = screen up) onto the device's.
nonisolated enum SkyAttitude {
    /// How the screen is rotated relative to the device.
    enum ScreenRotation: Sendable {
        case portrait
        /// Home side on the right: the device's top edge points left.
        case landscapeRight
        /// Home side on the left: the device's top edge points right.
        case landscapeLeft
        case portraitUpsideDown
    }

    /// Reference frame (x north, y west, z up) → our world (x east, y up, z south).
    static let referenceToWorld = simd_double3x3(columns: (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0)))

    /// - Parameters:
    ///   - referenceToDevice: `CMAttitude.rotationMatrix` as written (rows m11 m12 m13, …).
    ///   - screen: the current screen rotation.
    static func cameraOrientation(referenceToDevice: simd_double3x3, screen: ScreenRotation) -> simd_quatf {
        let screenToWorld = referenceToWorld * referenceToDevice.transpose * screenToDevice(screen)
        return simd_quatf(simd_float3x3(columns: (SIMD3<Float>(screenToWorld.columns.0),
                                                  SIMD3<Float>(screenToWorld.columns.1),
                                                  SIMD3<Float>(screenToWorld.columns.2))))
    }

    /// Columns: the screen's right, up and out-of-screen axes in device coordinates.
    static func screenToDevice(_ screen: ScreenRotation) -> simd_double3x3 {
        switch screen {
        case .portrait:
            simd_double3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)))
        case .landscapeRight:
            simd_double3x3(columns: (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)))
        case .landscapeLeft:
            simd_double3x3(columns: (SIMD3(0, 1, 0), SIMD3(-1, 0, 0), SIMD3(0, 0, 1)))
        case .portraitUpsideDown:
            simd_double3x3(columns: (SIMD3(-1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1)))
        }
    }

    /// Where gravity should point in device coordinates if `referenceToDevice` is used as above:
    /// the world's "down" (0, 0, -1 in the reference frame) carried into the device frame.
    /// Compared with CoreMotion's own gravity vector as a convention check.
    static func predictedGravity(referenceToDevice: simd_double3x3) -> SIMD3<Double> {
        referenceToDevice * SIMD3(0, 0, -1)
    }

    /// Smoothing that follows quickly while the phone turns and steadies it while it's held still
    /// (jitter only shows when still). Blends linearly from `still` at rest to `moving` at `fastSpeed`.
    static func smoothing(rotationSpeed: Double, still: Double, moving: Double, fastSpeed: Double) -> Double {
        let t = min(1, max(0, rotationSpeed / fastSpeed))
        return still + (moving - still) * t
    }

    /// Frame-rate-independent smoothing: `perFrame` is the slerp fraction for one 60 Hz frame.
    static func smoothingFraction(perFrame: Double, elapsed: Double) -> Float {
        Float(1 - pow(1 - perFrame, max(0, elapsed) * 60))
    }
}
