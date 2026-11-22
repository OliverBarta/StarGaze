@preconcurrency import AVFoundation
import os

/// The live camera feed behind the sky (back wide camera, preview only). One shared session, so
/// the sky photo can pause it and wait until the camera is really free (only one session can own
/// the camera). All AVFoundation work runs on a private serial queue.
nonisolated final class CameraPreviewSession: @unchecked Sendable {
    static let shared = CameraPreviewSession()

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "StarGaze.CameraPreview")
    private let logger = Logger(subsystem: "com.oliver.StarGaze", category: "CameraPreview")

    // Only touched on `queue`.
    private var configured = false
    /// A sky view is on screen and wants the feed.
    private var wanted = false
    /// The sky photo has the camera.
    private var paused = false
    /// The photo reconfigured the camera (fixed exposure, focus, format); undo that before resuming.
    private var needsRestore = false
    /// Tells the sky view the field of view may have changed (after start and after each photo).
    private var onReady: (@MainActor () -> Void)?

    /// The camera in use, and its field of view along the long side of the frame (degrees) and frame
    /// size (sensor landscape orientation). Set once configured.
    private(set) var device: AVCaptureDevice?
    private(set) var longSideFieldOfView: Double = 0
    private(set) var frameSize: (long: Double, short: Double) = (16, 9)

    /// A back camera exists (false in the simulator).
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Starts the feed when a sky view appears. Asks for camera permission the first time.
    /// `onReady` runs on the main queue once the camera is configured (for the field of view).
    func start(onReady: @escaping @MainActor () -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [self] granted in
            guard granted else { return }
            queue.async {
                self.wanted = true
                self.onReady = onReady
                self.configureIfNeeded()
                self.update()
                self.notifyReady()
            }
        }
    }

    /// Stops the feed when the sky view goes away.
    func stop() {
        queue.async {
            self.wanted = false
            self.update()
        }
    }

    /// Frees the camera for the sky photo. Returns once the session has actually stopped.
    func pauseForPhoto() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.paused = true
                self.update()
                continuation.resume()
            }
        }
    }

    /// Gives the camera back to the preview after the sky photo.
    func resumeAfterPhoto() {
        queue.async {
            self.paused = false
            self.needsRestore = true
            self.update()
            self.notifyReady()
        }
    }

    // MARK: - On `queue`

    private func update() {
        let shouldRun = wanted && !paused && configured
        if shouldRun && !session.isRunning {
            if needsRestore { restoreAutomaticSettings() }
            session.startRunning()  // blocks until running
        } else if !shouldRun && session.isRunning {
            session.stopRunning()  // blocks until stopped
        }
    }

    private func notifyReady() {
        guard let onReady else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { onReady() } }
    }

    /// The sky photo locks a long exposure, high ISO, focus and white balance, and picks its own
    /// format. Put the camera back to automatic preview settings and the preview's format.
    private func restoreAutomaticSettings() {
        needsRestore = false
        guard let device else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        session.commitConfiguration()
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("Couldn't restore preview camera settings: \(String(describing: error))")
        }
        readFormat(of: device)
    }

    private func readFormat(of device: AVCaptureDevice) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let a = Double(dimensions.width), b = Double(dimensions.height)
        frameSize = (max(a, b), min(a, b))
        longSideFieldOfView = Double(device.activeFormat.videoFieldOfView)
    }

    private func configureIfNeeded() {
        guard !configured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            logger.error("Can't add the camera to the preview session")
            return
        }
        session.addInput(input)
        session.commitConfiguration()
        readFormat(of: device)
        self.device = device
        configured = true
    }
}
