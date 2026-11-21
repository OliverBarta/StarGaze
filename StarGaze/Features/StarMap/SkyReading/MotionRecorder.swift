import CoreMotion
import simd

/// Records device motion while a sky photo is taken, for orientation and blur.
final class MotionRecorder {
    private let manager = CMMotionManager()
    private var samples: [MotionSample] = []
    /// Whether this recording is relative to true north (needs compass + location).
    private(set) var isTrueNorth = false

    func start() {
        samples = []
        guard manager.isDeviceMotionAvailable else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        isTrueNorth = frames.contains(.xTrueNorthZVertical)
        manager.deviceMotionUpdateInterval = SkyReadingTuning.motionUpdateInterval
        manager.startDeviceMotionUpdates(using: isTrueNorth ? .xTrueNorthZVertical : .xArbitraryCorrectedZVertical,
                                         to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let q = motion.attitude.quaternion
            let r = motion.rotationRate
            self.samples.append(MotionSample(
                timestamp: motion.timestamp,
                attitude: simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w),
                rotationRate: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot(),
                gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)))
        }
    }

    /// Stops recording and returns what was recorded.
    func stop() -> [MotionSample] {
        manager.stopDeviceMotionUpdates()
        defer { samples = [] }
        return samples
    }
}
