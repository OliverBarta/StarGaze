@preconcurrency import AVFoundation
import VideoToolbox

/// Takes one long-exposure still with the back wide camera. The live preview
/// (`CameraPreviewSession`) must be paused first, since only one session can own the camera. All AVFoundation work runs on a private serial queue.
///
/// Settings: the longest exposure the format allows (up to `targetExposureSeconds`), high ISO,
/// focus locked near infinity, white balance locked, flash off, and `.speed` quality
/// prioritization so there's no multi-frame (night mode style) fusion.
nonisolated final class SkyPhotoCapturer: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StarGaze.SkyPhotoCapturer")

    // Only touched on `queue` (delegate callbacks hop onto it).
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var output: AVCapturePhotoOutput?
    private var fieldOfView: Float = 0
    private var continuation: CheckedContinuation<CapturedSkyPhoto, Error>?
    /// Identifies the current shot, so an old shot's timeout can't end a newer one.
    private var shotID = 0
    private var image: CGImage?
    private var metadata: [String: Any] = [:]
    private var exposureStart: Double = 0
    private var exposureEnd: Double = 0

    /// A back camera exists and the user has allowed camera access.
    static var isAvailable: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func capture() async throws -> CapturedSkyPhoto {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.start()
            }
        }
    }

    // MARK: - Setup (on `queue`)

    private func start() {
        shotID += 1
        let id = shotID
        queue.asyncAfter(deadline: .now() + SkyReadingTuning.captureTimeoutSeconds) { [weak self] in
            guard let self, self.shotID == id else { return }
            self.finish(.failure(SkyPhotoError.timedOut))
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return finish(.failure(SkyPhotoError.noCamera))
        }
        guard let (format, dimensions) = Self.bestFormat(for: device) else {
            return finish(.failure(SkyPhotoError.configurationFailed))
        }

        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        session.beginConfiguration()
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input),
              session.canAddOutput(output) else {
            session.commitConfiguration()
            return finish(.failure(SkyPhotoError.configurationFailed))
        }
        session.addInput(input)
        session.addOutput(output)
        do {
            try device.lockForConfiguration()
            device.activeFormat = format  // switches the session to .inputPriority
            configureFixedSettings(device)
            device.unlockForConfiguration()
        } catch {
            session.commitConfiguration()
            return finish(.failure(SkyPhotoError.configurationFailed))
        }
        output.maxPhotoDimensions = dimensions
        session.commitConfiguration()

        self.session = session
        self.device = device
        self.output = output
        fieldOfView = format.videoFieldOfView
        session.startRunning()  // blocks until running (we're on our own queue)
        guard session.isRunning else { return finish(.failure(SkyPhotoError.sessionDidNotStart)) }

        // Exposure is applied after the session runs; the handler fires once frames use it.
        let exposure = Self.exposure(for: format)
        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: exposure.duration, iso: exposure.iso) { [weak self] _ in
                guard let self else { return }
                let settle = exposure.duration.seconds * Double(SkyReadingTuning.settleFrames)
                self.queue.asyncAfter(deadline: .now() + settle) { self.shoot() }
            }
            device.unlockForConfiguration()
        } catch {
            finish(.failure(SkyPhotoError.configurationFailed))
        }
    }

    /// Focus, white balance and low-light boost. Called with the device locked.
    private func configureFixedSettings(_ device: AVCaptureDevice) {
        if device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: SkyReadingTuning.focusLensPosition, completionHandler: nil)
        }
        if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: SkyReadingTuning.whiteBalanceTemperature, tint: 0)
            var gains = device.deviceWhiteBalanceGains(for: values)
            let maxGain = device.maxWhiteBalanceGain
            gains.redGain = min(max(gains.redGain, 1), maxGain)
            gains.greenGain = min(max(gains.greenGain, 1), maxGain)
            gains.blueGain = min(max(gains.blueGain, 1), maxGain)
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
    }

    /// The format with the longest allowed exposure, then the most pixels within our memory cap.
    private static func bestFormat(for device: AVCaptureDevice) -> (AVCaptureDevice.Format, CMVideoDimensions)? {
        var best: (format: AVCaptureDevice.Format, dimensions: CMVideoDimensions, exposure: Double, pixels: Int)?
        for format in device.formats {
            let fitting = format.supportedMaxPhotoDimensions.filter {
                Int($0.width) * Int($0.height) <= SkyReadingTuning.maxPhotoPixels
            }
            guard let dimensions = fitting.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
            else { continue }
            // Longer exposure only counts up to what we'd use anyway.
            let exposure = min(format.maxExposureDuration.seconds, SkyReadingTuning.targetExposureSeconds)
            let pixels = Int(dimensions.width) * Int(dimensions.height)
            if let current = best, (exposure, pixels) <= (current.exposure, current.pixels) { continue }
            best = (format, dimensions, exposure, pixels)
        }
        return best.map { ($0.format, $0.dimensions) }
    }

    private static func exposure(for format: AVCaptureDevice.Format) -> (duration: CMTime, iso: Float) {
        let seconds = min(SkyReadingTuning.targetExposureSeconds, format.maxExposureDuration.seconds)
        let duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
        let iso = min(max(format.maxISO * SkyReadingTuning.isoFraction, format.minISO), format.maxISO)
        return (duration, iso)
    }

    // MARK: - Shooting (on `queue`)

    private func shoot() {
        guard continuation != nil, let output else { return }
        let bgra = kCVPixelFormatType_32BGRA
        let settings = output.availablePhotoPixelFormatTypes.contains(bgra)
            ? AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: bgra])
            : AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.photoQualityPrioritization = .speed
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async { self.exposureStart = now }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async { self.exposureEnd = now }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? Self.cgImage(from: photo) : nil
        let metadata = photo.metadata
        queue.async {
            self.image = image
            self.metadata = metadata
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        queue.async {
            guard let image = self.image, let device = self.device else {
                return self.finish(.failure(SkyPhotoError.captureFailed))
            }
            let exif = self.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let exposure = exif?[kCGImagePropertyExifExposureTime as String] as? Double ?? device.exposureDuration.seconds
            let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Double])?.first ?? Double(device.iso)
            let end = self.exposureEnd > self.exposureStart ? self.exposureEnd : self.exposureStart + exposure
            self.finish(.success(CapturedSkyPhoto(
                image: image, exposureSeconds: exposure, iso: iso,
                fieldOfViewDegrees: self.fieldOfView, exposureStart: self.exposureStart, exposureEnd: end)))
        }
    }

    /// Uncompressed BGRA when available, otherwise decodes the compressed file data.
    private static func cgImage(from photo: AVCapturePhoto) -> CGImage? {
        if let buffer = photo.pixelBuffer {
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            return image
        }
        guard let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Resumes the caller once, stops the camera and resets for the next shot.
    private func finish(_ result: Result<CapturedSkyPhoto, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.stopRunning()
        session = nil
        device = nil
        output = nil
        image = nil
        metadata = [:]
        exposureStart = 0
        exposureEnd = 0
        continuation.resume(with: result)
    }
}
