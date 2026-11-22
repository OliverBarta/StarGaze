import Foundation
import Observation
import UIKit
import os

/// Runs the sky photo after a capture: countdown, pause the camera preview, shoot, resume it, then analyze
/// in the background (star detection, then Gemini's quality check). SkyScreen collects the
/// constellation (or not) once the reading is back.
@Observable
final class SkyPhotoSession {
    private(set) var phase: SkyPhotoPhase = .idle
    /// Bumps when the shutter has fired (drives the flash).
    private(set) var shutterCount = 0
    /// Analyses still running. They don't block the next photo.
    private var analysesRunning = 0
    /// The constellation being photographed (shown on the "Hold still" card).
    private(set) var subjectName: String?

    @ObservationIgnored private let capturer = SkyPhotoCapturer()
    @ObservationIgnored private let motion = MotionRecorder()
    @ObservationIgnored private let gemini = GeminiService()
    @ObservationIgnored private let logger = Logger(subsystem: "com.oliver.StarGaze", category: "SkyPhoto")

    /// Counting down or shooting. Analysis doesn't count, so the next find can be captured meanwhile.
    var isBusy: Bool { phase != .idle }
    var isAnalyzing: Bool { analysesRunning > 0 }

    /// A photo can be taken on this device right now (real camera, permission granted).
    static var canShoot: Bool { SkyPhotoCapturer.isAvailable }

    /// Starts the photo. `onShutter` is called exactly once, when the shutter has fired or as soon
    /// as it's clear there won't be a photo. `onDone` is called exactly once afterwards, with the
    /// reading, or nil if there was no photo.
    func shoot(_ context: SkyShotContext, onShutter: @escaping () -> Void = {},
               onDone: @escaping (SkyPhotoReading?) -> Void) {
        guard !isBusy else {
            onShutter()
            onDone(nil)
            return
        }
        Task { await run(context, onShutter: onShutter, onDone: onDone) }
    }

    private func run(_ context: SkyShotContext, onShutter: @escaping () -> Void,
                     onDone: @escaping (SkyPhotoReading?) -> Void) async {
        subjectName = context.constellationName
        defer { subjectName = nil }
        for n in stride(from: SkyReadingTuning.countdownSeconds, to: 1, by: -1) {
            phase = .countdown(n)
            try? await Task.sleep(for: .seconds(1))
        }
        phase = .countdown(1)
        motion.start()
        // only one session can own the camera: stop the live preview and wait until it has
        await CameraPreviewSession.shared.pauseForPhoto()
        try? await Task.sleep(for: SkyReadingTuning.cameraReleaseDelay)
        phase = .shooting

        let photo: SkyPhoto
        do {
            let captured = try await capturer.capture()
            let summary = ShotMotion.summarize(motion.stop(), from: captured.exposureStart,
                                               to: captured.exposureEnd)
            photo = SkyPhoto(context: context, captured: captured, motion: summary)
        } catch {
            logger.error("Sky photo failed: \(String(describing: error))")
            _ = motion.stop()
            CameraPreviewSession.shared.resumeAfterPhoto()
            onShutter()
            phase = .idle
            onDone(nil)
            return
        }
        CameraPreviewSession.shared.resumeAfterPhoto()
        shutterCount += 1
        onShutter()
        phase = .idle

        subjectName = nil
        analysesRunning += 1
        let reading = await analyze(photo)
        analysesRunning -= 1
        onDone(reading)
    }

    /// Star detection, then Gemini's quality check with what the phone knows, then the estimate.
    /// Failures only make the reading unreliable; they never affect the find itself.
    private func analyze(_ photo: SkyPhoto) async -> SkyPhotoReading {
        let detected = await Self.detectStars(in: photo)

        let context = SkyAnalysisContext(
            constellationName: photo.context.constellationName,
            brightestStars: TargetStarCatalog.brightestStars(constellationID: photo.context.constellationID,
                                                             limit: SkyReadingTuning.contextStarCount),
            detectedStars: detected?.starCount
        )
        let analysis: SkyAnalysis?
        do {
            analysis = try await gemini.analyzeSky(Self.uprightImage(of: photo), context: context,
                                                   timeout: SkyReadingTuning.geminiTimeoutSeconds)
        } catch {
            logger.error("Gemini sky check failed: \(String(describing: error))")
            analysis = nil
        }
        let device = Self.deviceEvidence(photo, detected)
        let sky = SunMoonAstronomy.sky(at: photo.context.takenAt, latitude: photo.context.latitude,
                                       longitude: photo.context.longitude)
        let reading = SkyReadingEstimator.reading(from: SkyReadingEstimator.Input(
            context: photo.context, source: .camera, deviceModel: DeviceModel.identifier,
            exposureSeconds: photo.captured.exposureSeconds, iso: Double(photo.captured.iso),
            detection: detected, analysis: analysis, device: device, sky: sky,
            hasLocation: photo.context.hasLocation
        ))
        #if DEBUG
        let stars = detected.map {
            String(format: " · %d stars (−%d) · glow %.4f", $0.starCount, $0.rejections.total, $0.relativeSkyGlow)
        } ?? ""
        let geminiText = analysis.map {
            String(format: " · Gemini B%d %@%@", $0.skyBrightness, $0.targetPatternVisible ? "pattern " : "",
                   $0.confidence.rawValue)
        } ?? " · Gemini failed"
        let issues = reading.issues.isEmpty ? "OK" : reading.issues.map(\.label).joined(separator: ", ")
        let line = photo.debugSummary + stars + geminiText + " · B\(reading.bortle) · \(issues)"
        logger.debug("Sky photo: \(line)")
        #endif
        return reading
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
    private nonisolated static func detectStars(in photo: SkyPhoto) async -> StarDetectionResult? {
        guard let image = LuminanceImage(cgImage: photo.captured.image,
                                         maxDimension: SkyReadingTuning.detectionMaxDimension) else { return nil }
        return StarDetector.detect(in: image, exposureSeconds: photo.captured.exposureSeconds,
                                   iso: photo.captured.iso)
    }
}
