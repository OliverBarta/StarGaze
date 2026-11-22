@preconcurrency import AVFoundation
import SceneKit
import UIKit

/// The live sky: the camera feed (`AVCaptureVideoPreviewLayer`) with a transparent SceneKit view
/// on top. Keeps the SceneKit camera's field of view equal to what the preview actually shows, so
/// the drawn stars line up with the picture.
final class SkyCameraView: UIView {
    let sceneView: SCNView
    /// The SceneKit camera to keep in step with the preview's field of view.
    let cameraNode: SCNNode

    private let previewLayer = AVCaptureVideoPreviewLayer(session: CameraPreviewSession.shared.session)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    init(sceneView: SCNView, cameraNode: SCNNode) {
        self.sceneView = sceneView
        self.cameraNode = cameraNode
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        sceneView.backgroundColor = .clear
        sceneView.isOpaque = false
        addSubview(sceneView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts the camera feed (asks for permission the first time).
    func startPreview() {
        CameraPreviewSession.shared.start { [weak self] in
            self?.cameraReady()
        }
    }

    func stopPreview() {
        CameraPreviewSession.shared.stop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        sceneView.frame = bounds
        updateFieldOfView()
    }

    private func cameraReady() {
        if rotationCoordinator == nil, let device = CameraPreviewSession.shared.device {
            // Keep the picture upright in every screen orientation.
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            applyRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) {
                [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyRotation(angle) } }
            }
        }
        if let connection = previewLayer.connection, connection.isVideoStabilizationSupported {
            // stabilization shifts the picture against the motion-driven sky
            connection.preferredVideoStabilizationMode = .off
        }
        updateFieldOfView()
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
        updateFieldOfView()
    }

    /// Vertical field of view of what's visible on screen. The preview fills the view (cropping
    /// the frame), so the visible part depends on the camera's field of view, the frame's aspect
    /// ratio, the view's aspect ratio and whether the screen is portrait or landscape.
    private func updateFieldOfView() {
        let session = CameraPreviewSession.shared
        guard session.longSideFieldOfView > 0, bounds.width > 0, bounds.height > 0 else { return }
        let tanLong = tan(session.longSideFieldOfView * .pi / 360)
        let tanShort = tanLong * session.frameSize.short / session.frameSize.long
        let portrait = bounds.height >= bounds.width
        // tangents of the half-angles of the (rotated) frame as it appears on screen
        let frameTanX = portrait ? tanShort : tanLong
        let frameTanY = portrait ? tanLong : tanShort
        let viewAspect = Double(bounds.width / bounds.height)
        let visibleTanY = viewAspect < frameTanX / frameTanY ? frameTanY : frameTanX / viewAspect
        cameraNode.camera?.projectionDirection = .vertical
        cameraNode.camera?.fieldOfView = CGFloat(2 * atan(visibleTanY) * 180 / .pi)
    }
}
