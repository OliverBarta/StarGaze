import SwiftUI
import ARKit
import SceneKit

/// Draws tonight's constellations as glowing stars + soft lines.
/// - useAR = true  (real iPhone): drawn over the live camera, follows where you point.
/// - useAR = false (simulator):   a dark "virtual sky" you drag around to look.
/// Tapping a star or line reports which constellation was tapped.
struct SkySceneView: UIViewRepresentable {
    let useAR: Bool
    let constellations: [PlacedConstellation]
    let version: Int  // bumps whenever positions are recalculated
    let onTap: (PlacedConstellation) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(useAR: useAR, onTap: onTap)
    }

    func makeUIView(context: Context) -> SCNView {
        let c = context.coordinator
        let view: SCNView

        if useAR {
            let ar = ARSCNView()
            ar.scene = SCNScene()
            ar.automaticallyUpdatesLighting = false
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravityAndHeading  // -z = true north, +y = up
            ar.session.run(config)
            view = ar
        } else {
            view = SCNView()
            view.scene = SCNScene()
            view.scene?.background.contents = UIColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1)
            view.pointOfView = c.virtualCamera
            view.scene?.rootNode.addChildNode(c.virtualCamera)
            c.addBackgroundStars()
            view.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:))))
        }

        view.antialiasingMode = .multisampling4X
        view.scene?.rootNode.addChildNode(c.skyRoot)
        view.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleTap(_:))))
        c.view = view
        c.addCompassLabels()
        c.startTimer()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.rebuild(constellations, version: version)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stopTimer()
        (view as? ARSCNView)?.session.pause()
    }

    final class Coordinator: NSObject {
        let useAR: Bool
        var onTap: (PlacedConstellation) -> Void
        weak var view: SCNView?

        let skyRoot = SCNNode()                 // everything in the sky hangs off this
        private let constellationRoot = SCNNode()
        let virtualCamera = SCNNode()

        private var placed: [PlacedConstellation] = []
        private var builtVersion = -1
        private var timer: Timer?
        private let radius: Float = 30          // how far away (metres) the sky is drawn

        // Virtual-sky look direction (radians). Starts facing southeast, tilted up.
        private var yaw: Float = -135 * .pi / 180
        private var pitch: Float = 0.45

        init(useAR: Bool, onTap: @escaping (PlacedConstellation) -> Void) {
            self.useAR = useAR
            self.onTap = onTap
            super.init()
            skyRoot.addChildNode(constellationRoot)

            let camera = SCNCamera()
            camera.fieldOfView = 70
            camera.zNear = 0.1
            camera.zFar = 200
            virtualCamera.camera = camera
            updateVirtualCamera()
        }

        // MARK: - Drawing the constellations

        func rebuild(_ list: [PlacedConstellation], version: Int) {
            guard version != builtVersion else { return }
            builtVersion = version
            placed = list

            let old = constellationRoot.childNodes
            for i in 0..<old.count { old[i].removeFromParentNode() }

            for i in 0..<list.count where list[i].centerAlt > -10 {
                constellationRoot.addChildNode(makeNode(for: list[i]))
            }
        }

        private func makeNode(for c: PlacedConstellation) -> SCNNode {
            let node = SCNNode()
            node.name = c.id
            let lineMaterial = Self.flatMaterial(UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 0.45))
            var seen = Set<String>()

            for s in 0..<c.segments.count {
                let seg = c.segments[s]
                for i in 0..<seg.count {
                    // one glowing star per unique point (segments share stars)
                    let key = "\(Int(seg[i].x * 1000)),\(Int(seg[i].y * 1000)),\(Int(seg[i].z * 1000))"
                    if !seen.contains(key) {
                        seen.insert(key)
                        node.addChildNode(Self.star(at: seg[i] * radius, size: 1.0, brightness: 1.0))
                    }
                    if i + 1 < seg.count {
                        node.addChildNode(Self.line(from: seg[i] * radius, to: seg[i + 1] * radius,
                                                    material: lineMaterial))
                    }
                }
            }

            node.addChildNode(Self.label(c.name, at: c.center * (radius * 0.97),
                                         color: UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1), size: 0.11))
            return node
        }

        /// N / E / S / W markers on the horizon so you know which way you're facing.
        func addCompassLabels() {
            let names = ["N", "E", "S", "W"]
            for i in 0..<names.count {
                let dir = Astronomy.arDirection(altDeg: 2, azDeg: Double(i) * 90)
                skyRoot.addChildNode(Self.label(names[i], at: dir * radius,
                                                color: UIColor.white.withAlphaComponent(0.7), size: 0.15))
            }
            // Thin horizon ring
            let ring = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.03)
            ring.materials = [Self.flatMaterial(UIColor.white.withAlphaComponent(0.25))]
            skyRoot.addChildNode(SCNNode(geometry: ring))
        }

        /// Faint random stars so the virtual sky doesn't look empty.
        func addBackgroundStars() {
            for _ in 0..<350 {
                let alt = Double.random(in: -5...90)
                let az = Double.random(in: 0..<360)
                let dir = Astronomy.arDirection(altDeg: alt, azDeg: az)
                skyRoot.addChildNode(Self.star(at: dir * (radius * 1.05),
                                               size: Float.random(in: 0.25...0.5),
                                               brightness: CGFloat.random(in: 0.3...0.7)))
            }
        }

        // MARK: - Building blocks

        /// Soft round glow, generated once and shared by every star.
        private static let glowImage: UIImage = {
            let size = CGSize(width: 64, height: 64)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [UIColor.white.cgColor,
                              UIColor(red: 0.75, green: 0.88, blue: 1, alpha: 0.55).cgColor,
                              UIColor.clear.cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: colors, locations: [0, 0.22, 1])!
                let mid = CGPoint(x: 32, y: 32)
                ctx.cgContext.drawRadialGradient(gradient, startCenter: mid, startRadius: 0,
                                                 endCenter: mid, endRadius: 32, options: [])
            }
        }()

        private static func star(at position: SIMD3<Float>, size: Float, brightness: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
            let m = SCNMaterial()
            m.diffuse.contents = glowImage
            m.lightingModel = .constant
            m.blendMode = .add
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            plane.materials = [m]

            let node = SCNNode(geometry: plane)
            node.simdPosition = position
            node.opacity = brightness
            node.constraints = [SCNBillboardConstraint()]

            // gentle twinkle
            let low = brightness * 0.6
            let duration = Double.random(in: 1.2...2.8)
            let twinkle = SCNAction.sequence([.fadeOpacity(to: low, duration: duration),
                                              .fadeOpacity(to: brightness, duration: duration)])
            node.runAction(.repeatForever(twinkle))
            return node
        }

        private static func label(_ text: String, at position: SIMD3<Float>, color: UIColor, size: Float) -> SCNNode {
            let geometry = SCNText(string: text, extrusionDepth: 0)
            var font = UIFont.systemFont(ofSize: 10, weight: .semibold)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = UIFont(descriptor: rounded, size: 10)
            }
            geometry.font = font
            geometry.flatness = 0.15
            geometry.materials = [flatMaterial(color)]

            let label = SCNNode(geometry: geometry)
            let (minB, maxB) = label.boundingBox
            label.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
            label.scale = SCNVector3(size, size, size)

            let holder = SCNNode()
            holder.simdPosition = position
            holder.addChildNode(label)
            holder.constraints = [SCNBillboardConstraint()]
            return holder
        }

        private static func flatMaterial(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            m.readsFromDepthBuffer = false  // never hidden behind real-world things
            return m
        }

        /// A thin cylinder between two points.
        private static func line(from a: SIMD3<Float>, to b: SIMD3<Float>, material: SCNMaterial) -> SCNNode {
            let v = b - a
            let length = simd_length(v)
            let cylinder = SCNCylinder(radius: 0.035, height: CGFloat(length))
            cylinder.materials = [material]
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (a + b) / 2
            if length > 0 {
                node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: v / length)
            }
            return node
        }

        // MARK: - Gestures

        /// Tap: find the constellation whose star (or centre) is closest to your finger.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, let camera = view.pointOfView else { return }
            let tap = gesture.location(in: view)
            let forward = camera.simdWorldFront
            let origin = skyRoot.simdWorldPosition

            var best: PlacedConstellation?
            var bestDistance: Float = 55  // must be within 55 points of a star

            for i in 0..<placed.count {
                let c = placed[i]
                guard c.centerAlt > -10 else { continue }
                var points: [SIMD3<Float>] = [c.center]
                for s in 0..<c.segments.count {
                    points.append(contentsOf: c.segments[s])
                }
                for p in 0..<points.count {
                    let dir = points[p]
                    guard simd_dot(forward, dir) > 0 else { continue }  // behind you
                    let world = origin + dir * radius
                    let screen = view.projectPoint(SCNVector3(world.x, world.y, world.z))
                    let d = hypotf(screen.x - Float(tap.x), screen.y - Float(tap.y))
                    if d < bestDistance {
                        bestDistance = d
                        best = c
                    }
                }
            }
            if let best { onTap(best) }
        }

        /// Virtual sky only: drag to look around.
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let t = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            yaw += Float(t.x) * 0.005
            pitch = min(1.5, max(-0.3, pitch + Float(t.y) * 0.005))
            updateVirtualCamera()
        }

        private func updateVirtualCamera() {
            virtualCamera.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        // MARK: - Keep the sky centred on you (AR)

        func startTimer() {
            guard useAR else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.followCamera() }
            }
        }

        func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        /// Stars are "infinitely" far away, so the sky moves with you.
        private func followCamera() {
            guard let camera = view?.pointOfView else { return }
            skyRoot.simdPosition = camera.simdWorldPosition
        }
    }
}
