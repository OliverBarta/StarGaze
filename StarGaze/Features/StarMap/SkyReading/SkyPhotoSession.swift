import Foundation
import Observation
import os

/// Runs the sky photo after a capture: countdown, pause ARKit, shoot, resume ARKit, analyze.
/// The constellation is already collected before this starts; nothing here can undo or block that.
@Observable
final class SkyPhotoSession {
    private(set) var phase: SkyPhotoPhase = .idle
    /// SkySceneView pauses its ARSession while this is true, so the camera is free.
    private(set) var arPaused = false
    /// Bumps when the shutter has fired (drives the flash).
    private(set) var shutterCount = 0
    /// DEBUG: exposure, ISO and motion of the last shot.
    private(set) var debugSummary: String?

    @ObservationIgnored private let capturer = SkyPhotoCapturer()
    @ObservationIgnored private let motion = MotionRecorder()
    @ObservationIgnored private let logger = Logger(subsystem: "com.oliver.StarGaze", category: "SkyPhoto")

    var isBusy: Bool { phase != .idle }

    /// A photo can be taken on this device right now (real camera, permission granted).
    static var canShoot: Bool { SkyPhotoCapturer.isAvailable }

    /// Starts the photo. `onShutter` is called exactly once: when the shutter has fired, or as
    /// soon as it's clear there won't be a photo.
    func shoot(_ context: SkyShotContext, onShutter: @escaping () -> Void) {
        guard !isBusy else { return onShutter() }
        Task { await run(context, onShutter: onShutter) }
    }

    private func run(_ context: SkyShotContext, onShutter: @escaping () -> Void) async {
        for n in stride(from: SkyReadingTuning.countdownSeconds, to: 1, by: -1) {
            phase = .countdown(n)
            try? await Task.sleep(for: .seconds(1))
        }
        phase = .countdown(1)
        motion.start()
        arPaused = true
        try? await Task.sleep(for: SkyReadingTuning.arReleaseDelay)
        phase = .shooting

        let photo: SkyPhoto
        do {
            let captured = try await capturer.capture()
            let summary = ShotMotion.summarize(motion.stop(), from: captured.exposureStart,
                                               to: captured.exposureEnd, isTrueNorth: motion.isTrueNorth)
            photo = SkyPhoto(context: context, captured: captured, motion: summary)
        } catch {
            logger.error("Sky photo failed: \(String(describing: error))")
            _ = motion.stop()
            arPaused = false
            onShutter()
            phase = .idle
            return
        }
        arPaused = false
        shutterCount += 1
        onShutter()

        phase = .analyzing
        await analyze(photo)
        phase = .idle
    }

    /// Parts 2–4 (star detection, Gemini, the estimate) plug in here. For now the photo is only
    /// inspected in DEBUG builds, then dropped; nothing is persisted.
    private func analyze(_ photo: SkyPhoto) async {
        #if DEBUG
        showDebugSummary(photo.debugSummary)
        if DebugPhotoSaver.isEnabled {
            await DebugPhotoSaver.save(photo)
        }
        #endif
    }

    #if DEBUG
    private func showDebugSummary(_ text: String) {
        debugSummary = text
        logger.debug("Sky photo: \(text)")
        Task {
            try? await Task.sleep(for: SkyReadingTuning.debugSummaryDuration)
            if debugSummary == text { debugSummary = nil }
        }
    }
    #endif
}
