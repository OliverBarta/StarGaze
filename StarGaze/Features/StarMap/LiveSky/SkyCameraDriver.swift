import CoreMotion
import QuartzCore
import SceneKit
import UIKit
import os
import simd

/// Points the live sky's SceneKit camera wherever the phone points, from CoreMotion device motion
/// (gyroscope + accelerometer + compass), like star-map apps do. Unlike ARKit world tracking, it
/// needs no visual features, so it works against a featureless night sky, and the compass keeps
/// correcting the heading instead of reading it only once.
final class SkyCameraDriver: NSObject {
    let cameraNode: SCNNode
    /// Called when heading accuracy becomes poor (true) or good again (false), after a short delay.
    var onNeedsCalibration: (Bool) -> Void = { _ in }
    /// Used to read the screen's current rotation.
    weak var hostView: UIView?

    private let manager = CMMotionManager()
    private var displayLink: CADisplayLink?
    private var smoothed: simd_quatf?
    private var lastStep: CFTimeInterval?
    /// True if CoreMotion's matrix turns out to map device → reference instead (decided once from gravity).
    private var transposeAttitude: Bool?
    private var needsCalibration = false
    private var calibrationChangedAt: CFTimeInterval?
    private let logger = Logger(subsystem: "com.oliver.StarGaze", category: "SkyCamera")

    /// Device motion with a compass-based reference frame is available (false in the simulator).
    static var isAvailable: Bool {
        CMMotionManager().isDeviceMotionAvailable
            && CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
    }

    init(cameraNode: SCNNode) {
        self.cameraNode = cameraNode
        super.init()
    }

    func start() {
        guard displayLink == nil, manager.isDeviceMotionAvailable else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        // True north needs location; magnetic north is a few degrees off but better than nothing.
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical
                                                                                     : .xMagneticNorthZVertical
        if frame != .xTrueNorthZVertical { logger.notice("True north unavailable; using magnetic north") }
        manager.deviceMotionUpdateInterval = TargetingTuning.motionUpdateInterval
        manager.startDeviceMotionUpdates(using: frame)
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        manager.stopDeviceMotionUpdates()
        smoothed = nil
        lastStep = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let motion = manager.deviceMotion else { return }
        let m = motion.attitude.rotationMatrix
        var r = simd_double3x3(rows: [SIMD3(m.m11, m.m12, m.m13),
                                      SIMD3(m.m21, m.m22, m.m23),
                                      SIMD3(m.m31, m.m32, m.m33)])
        decideConvention(r, gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z))
        if transposeAttitude == true { r = r.transpose }

        let target = SkyAttitude.cameraOrientation(referenceToDevice: r, screen: screenRotation())
        let now = link.timestamp
        let elapsed = lastStep.map { now - $0 } ?? 1.0 / 60.0
        lastStep = now
        if let current = smoothed {
            let r = motion.rotationRate
            let speed = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            let perFrame = SkyAttitude.smoothing(rotationSpeed: speed, still: TargetingTuning.attitudeSmoothing,
                                                 moving: TargetingTuning.attitudeSmoothingMoving,
                                                 fastSpeed: TargetingTuning.fastRotationRadiansPerSecond)
            let t = SkyAttitude.smoothingFraction(perFrame: perFrame, elapsed: elapsed)
            smoothed = simd_slerp(current, target, t)
        } else {
            smoothed = target
        }
        if let smoothed { cameraNode.simdOrientation = smoothed }

        updateCalibration(motion.magneticField.accuracy, now: now)
    }

    /// CoreMotion's gravity vector tells us which way the rotation matrix goes. Decided once, from
    /// a tilted sample where the two possibilities clearly differ.
    private func decideConvention(_ r: simd_double3x3, gravity: SIMD3<Double>) {
        guard transposeAttitude == nil, simd_length(gravity) > 0.5 else { return }
        let asIs = SkyAttitude.predictedGravity(referenceToDevice: r)
        let flipped = SkyAttitude.predictedGravity(referenceToDevice: r.transpose)
        guard simd_distance(asIs, flipped) > 0.5 else { return }
        let g = simd_normalize(gravity)
        transposeAttitude = simd_distance(flipped, g) < simd_distance(asIs, g)
        if transposeAttitude == true { logger.notice("CoreMotion attitude used transposed") }
    }

    private func updateCalibration(_ accuracy: CMMagneticFieldCalibrationAccuracy, now: CFTimeInterval) {
        let poor = accuracy == .uncalibrated || accuracy == .low
        guard poor != needsCalibration else {
            calibrationChangedAt = nil
            return
        }
        let since = calibrationChangedAt ?? now
        calibrationChangedAt = since
        if now - since >= TargetingTuning.calibrationHintDelay {
            needsCalibration = poor
            calibrationChangedAt = nil
            onNeedsCalibration(poor)
        }
    }

    private func screenRotation() -> SkyAttitude.ScreenRotation {
        switch hostView?.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait {
        case .landscapeRight: .landscapeRight
        case .landscapeLeft: .landscapeLeft
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }
}
