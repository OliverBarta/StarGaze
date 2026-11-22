import CoreMotion

/// Records device motion while a sky photo is taken, for orientation and blur.
final class MotionRecorder {
    private let manager = CMMotionManager()
    private var samples: [MotionSample] = []
    func start() {
        samples = []
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = SkyReadingTuning.motionUpdateInterval
        // Only gravity and rotation rate are used, and neither depends on the heading reference.
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical,
                                         to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let r = motion.rotationRate
            self.samples.append(MotionSample(
                timestamp: motion.timestamp,
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
