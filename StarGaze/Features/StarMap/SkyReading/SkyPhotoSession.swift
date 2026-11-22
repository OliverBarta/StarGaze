import Foundation
import Observation
import UIKit
import os

/// Runs the sky photo after a capture: countdown, pause ARKit, shoot, resume ARKit, then analyze
/// in the background (star detection, then Gemini's quality check).
/// The constellation is already collected before this starts; nothing here can undo or block that.
@Observable
final class SkyPhotoSession {
    private(set) var phase: SkyPhotoPhase = .idle
    /// SkySceneView pauses its ARSession while this is true, so the camera is free.
    private(set) var arPaused = false
    /// Bumps when the shutter has fired (drives the flash).
    private(set) var shutterCount = 0
    /// Analyses still running. They don't block the next photo.
    private var analysesRunning = 0
    /// DEBUG: exposure, ISO and motion of the last shot.
    private(set) var debugSummary: String?

    @ObservationIgnored private let capturer = SkyPhotoCapturer()
    @ObservationIgnored private let motion = MotionRecorder()
    @ObservationIgnored private let gemini = GeminiService()
    @ObservationIgnored private let logger = Logger(subsystem: "com.oliver.StarGaze", category: "SkyPhoto")

    /// Counting down or shooting. Analysis doesn't count, so the next find can be captured meanwhile.
    var isBusy: Bool { phase != .idle }
    var isAnalyzing: Bool { analysesRunning > 0 }

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
        phase = .idle

        analysesRunning += 1
        await analyze(photo)
        analysesRunning -= 1
    }

    /// Star detection, then Gemini's quality check with what the phone knows. Failures only mean
    /// less information; nothing is persisted yet (Part 4 combines and saves the reading).
    private func analyze(_ photo: SkyPhoto) async {
        let detected = await Self.detectStars(in: photo)
        #if DEBUG
        let summary = photo.debugSummary + (detected.map {
            String(format: " · %d stars (−%d) · glow %.4f", $0.result.starCount,
                   $0.result.rejections.total, $0.result.relativeSkyGlow)
        } ?? "")
        showDebugSummary(summary)
        if DebugPhotoSaver.isEnabled {
            await DebugPhotoSaver.save(photo)
            if let detected {
                await DebugPhotoSaver.saveAnnotated(detected.image, detection: detected.result)
            }
        }
        #endif

        let context = SkyAnalysisContext(
            constellationName: photo.context.constellationName,
            brightestStars: TargetStarCatalog.brightestStars(constellationID: photo.context.constellationID,
                                                             limit: SkyReadingTuning.contextStarCount),
            detectedStars: detected?.result.starCount
        )
        let analysis: SkyAnalysis?
        do {
            analysis = try await gemini.analyzeSky(Self.uprightImage(of: photo), context: context,
                                                   timeout: SkyReadingTuning.geminiTimeoutSeconds)
        } catch {
            logger.error("Gemini sky check failed: \(String(describing: error))")
            analysis = nil
        }
        #if DEBUG
        if let analysis {
            let issues = SkyReadingIssue.issues(from: analysis, device: Self.deviceEvidence(photo, detected?.result))
                .map(\.label)
            showDebugSummary(summary + String(format: " · Gemini %d★ B%d %@%@ · %@", analysis.estimatedVisibleStars,
                                              analysis.skyBrightness, analysis.targetPatternVisible ? "pattern " : "",
                                              analysis.confidence.rawValue,
                                              issues.isEmpty ? "OK" : issues.joined(separator: ", ")))
        } else {
            showDebugSummary(summary + " · Gemini failed")
        }
        #endif
    }

    /// What the phone measured itself, which outranks Gemini on "sky?" and "blurred?".
    private nonisolated static func deviceEvidence(_ photo: SkyPhoto,
                                                   _ detection: StarDetectionResult?) -> SkyDeviceEvidence {
        let gravity = photo.motion?.gravity
        return SkyDeviceEvidence(
            cameraElevationDegrees: gravity.flatMap { SkyDeviceEvidence.cameraElevationDegrees(gravity: ($0.x, $0.y, $0.z)) },
            maxRotationDegreesPerSecond: photo.motion?.maxRotationDegreesPerSecond,
            detectedStars: detection?.starCount,
            elongatedRejections: detection?.rejections.elongated
        )
    }

    /// The photo rotated the way the phone was held, so Gemini sees the sky the right way up.
    private nonisolated static func uprightImage(of photo: SkyPhoto) -> UIImage {
        let orientation: UIImage.Orientation = switch photo.displayOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        }
        return UIImage(cgImage: photo.captured.image, scale: 1, orientation: orientation)
    }

    /// Off the main thread: linear luminance, hot-pixel-rejecting downscale, then detection.
    @concurrent
    private nonisolated static func detectStars(in photo: SkyPhoto) async -> (image: LuminanceImage,
                                                                              result: StarDetectionResult)? {
        guard let image = LuminanceImage(cgImage: photo.captured.image,
                                         maxDimension: SkyReadingTuning.detectionMaxDimension) else { return nil }
        let result = StarDetector.detect(in: image, exposureSeconds: photo.captured.exposureSeconds,
                                         iso: photo.captured.iso)
        return (image, result)
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
