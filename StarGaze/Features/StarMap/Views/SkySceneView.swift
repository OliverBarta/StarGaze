import SwiftUI
import ARKit
import SceneKit

/// Draws tonight's constellations as glowing, twinkling stars joined by soft light strands.
/// - useAR = true  (real iPhone): drawn over the live camera, follows where you point.
/// - useAR = false (simulator):   a dark "virtual sky" you drag around to look.
/// Whatever you point at lights up and shows its name; the rest fades back.
/// Tapping a star or line reports which constellation was tapped.
struct SkySceneView: UIViewRepresentable {
    let useAR: Bool
    let constellations: [PlacedConstellation]
    let version: Int  // bumps whenever positions are recalculated
    let discovered: Set<String>
    let stars: [PlacedStar]
    let namedStars: [PlacedNamedStar]
    /// Hidden while a cutscene covers the screen, so the GPU isn't drawing two scenes at once.
    var hidden = false
    let onTap: (PlacedConstellation) -> Void
    /// Name being held on and how far along (0...1), or nil when nothing is.
    let onDwell: (String?, Double) -> Void
    /// Fired once when you've held on a constellation long enough.
    let onDiscover: (PlacedConstellation) -> Void

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
            view.scene?.background.contents = Coordinator.nightGradient
            view.pointOfView = c.virtualCamera
            view.scene?.rootNode.addChildNode(c.virtualCamera)
            c.addGround()
            view.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:))))
        }

        view.antialiasingMode = .multisampling4X
        view.scene?.rootNode.addChildNode(c.skyRoot)
        view.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleTap(_:))))
        c.view = view
        c.addHorizon()
        c.startTimer()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        view.isHidden = hidden
        view.isPlaying = !hidden
        c.onTap = onTap
        c.onDwell = onDwell
        c.onDiscover = onDiscover
        c.discovered = discovered
        c.rebuild(constellations, stars: stars, namedStars: namedStars, version: version)
        c.refreshDiscoveredColors()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stopTimer()
        (view as? ARSCNView)?.session.pause()
    }

    /// The parts of one drawn constellation, so we can brighten/fade them.
    struct DrawnConstellation {
        let placed: PlacedConstellation
        let core: SCNMaterial
        let center: SIMD3<Float>
        let lines: SCNNode
        let stars: SCNNode
        let label: SCNNode
        let art: SCNNode?
    }

    final class Coordinator: NSObject {
        let useAR: Bool
        var onTap: (PlacedConstellation) -> Void
        var onDwell: (String?, Double) -> Void = { _, _ in }
        var onDiscover: (PlacedConstellation) -> Void = { _ in }
        var discovered: Set<String> = []
        weak var view: SCNView?

        // Discovering: hold within `dwellAngle` of a constellation for `dwellNeeded` seconds.
        private var dwellName: String?
        private var dwellTime: Double = 0
        private var lastReported: Double = -1
        private let dwellNeeded: Double = 1.5
        private let dwellAngle: Float = 10 * .pi / 180

        let skyRoot = SCNNode()                 // everything in the sky hangs off this
        private let constellationRoot = SCNNode()
        private let starFieldRoot = SCNNode()
        let virtualCamera = SCNNode()

        private var placed: [PlacedConstellation] = []
        private var drawn: [DrawnConstellation] = []
        private var builtVersion = -1
        private var timer: Timer?
        private let radius: Float = 30          // how far away (metres) the sky is drawn

        // Virtual-sky look direction (radians). Starts facing southeast, tilted up.
        private var yaw: Float = -135 * .pi / 180
        private var pitch: Float = 0.45

        // Palette
        private static let lineCore = UIColor(red: 0.70, green: 0.86, blue: 1.00, alpha: 1)
        private static let lineHalo = UIColor(red: 0.35, green: 0.55, blue: 1.00, alpha: 1)
        private static let discoveredCore = UIColor(red: 1.00, green: 0.80, blue: 0.40, alpha: 1)
        private static let labelColor = UIColor(red: 0.80, green: 0.88, blue: 1.00, alpha: 1)
        private static let starTints: [UIColor] = [
            UIColor(red: 0.85, green: 0.92, blue: 1.00, alpha: 1),  // blue-white
            UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),  // white
            UIColor(red: 1.00, green: 0.93, blue: 0.80, alpha: 1),  // warm
            UIColor(red: 1.00, green: 0.82, blue: 0.70, alpha: 1)   // orange-ish
        ]

        init(useAR: Bool, onTap: @escaping (PlacedConstellation) -> Void) {
            self.useAR = useAR
            self.onTap = onTap
            super.init()
            skyRoot.addChildNode(starFieldRoot)
            skyRoot.addChildNode(constellationRoot)

            let camera = SCNCamera()
            camera.fieldOfView = 70
            camera.zNear = 0.1
            camera.zFar = 200
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = false  // stop it auto-brightening the dark sky
            camera.exposureOffset = -0.3
            camera.bloomIntensity = 0.5       // soft glow around bright things
            camera.bloomThreshold = 0.9
            camera.bloomBlurRadius = 6
            virtualCamera.camera = camera
            updateVirtualCamera()
        }

        // MARK: - Drawing the constellations

        func rebuild(_ list: [PlacedConstellation], stars: [PlacedStar], namedStars: [PlacedNamedStar],
                     version: Int) {
            guard version != builtVersion else { return }
            builtVersion = version
            placed = list
            drawn = []
            buildStarField(stars, named: namedStars)

            let old = constellationRoot.childNodes
            for i in 0..<old.count { old[i].removeFromParentNode() }

            for i in 0..<list.count where list[i].centerAlt > -10 {
                let (node, parts) = makeNode(for: list[i])
                constellationRoot.addChildNode(node)
                drawn.append(parts)
            }
            updateFocus()
        }

        private func makeNode(for c: PlacedConstellation) -> (SCNNode, DrawnConstellation) {
            let node = SCNNode()
            node.name = c.id
            let lines = SCNNode()
            let stars = SCNNode()
            node.addChildNode(lines)
            node.addChildNode(stars)

            let core = Self.glowMaterial(Self.lineCore, opacity: 0.55)
            let halo = Self.glowMaterial(Self.lineHalo, opacity: 0.07)
            var seen = Set<String>()

            for s in 0..<c.segments.count {
                let seg = c.segments[s]
                for i in 0..<seg.count {
                    // one sparkle per unique point (segments share stars)
                    let key = "\(Int(seg[i].x * 1000)),\(Int(seg[i].y * 1000)),\(Int(seg[i].z * 1000))"
                    if !seen.contains(key) {
                        seen.insert(key)
                        // vary size + colour a little so it looks natural, but keep it
                        // stable for each star (based on its position, not random)
                        let variety = abs(seg[i].x * 37 + seg[i].y * 91 + seg[i].z * 53)
                        let size = 0.9 + Float(Int(variety * 100) % 5) * 0.12
                        let tint = Self.starTints[Int(variety * 1000) % Self.starTints.count]
                        stars.addChildNode(Self.sparkle(at: seg[i] * radius, size: size, tint: tint,
                                                        brightness: 1.0))
                    }
                    if i + 1 < seg.count {
                        let a = seg[i] * radius
                        let b = seg[i + 1] * radius
                        // shorten each strand so it doesn't run into the star glows
                        let gap = simd_normalize(b - a) * 0.45
                        lines.addChildNode(Self.strand(from: a + gap, to: b - gap, radius: 0.018, material: core))
                        lines.addChildNode(Self.strand(from: a + gap, to: b - gap, radius: 0.08, material: halo))
                    }
                }
            }

            // Name sits just below the constellation's centre
            let below = Astronomy.arDirection(altDeg: c.centerAlt - 4, azDeg: c.centerAz)
            let label = Self.label(c.name.uppercased(), at: below * (radius * 0.96),
                                   color: Self.labelColor, size: 0.085, spacing: 3.5, weight: .light)
            node.addChildNode(label)

            // Mythological illustration, warped onto the exact patch of sky
            var artNode: SCNNode?
            if let art = c.art, c.artGrid.count == (art.grid + 1) * (art.grid + 1),
               let image = SkyArt.image(named: art.file) {
                let mesh = Self.artMesh(grid: art.grid, directions: c.artGrid,
                                        radius: radius * 1.01, image: image)
                node.insertChildNode(mesh, at: 0)   // behind the lines
                artNode = mesh
            }

            return (node, DrawnConstellation(placed: c, core: core, center: c.center,
                                             lines: lines, stars: stars, label: label, art: artNode))
        }

        /// Subtle horizon ring + compass letters so you know which way you're facing.
        func addHorizon() {
            let names = ["N", "E", "S", "W"]
            for i in 0..<names.count {
                let dir = Astronomy.arDirection(altDeg: 1.5, azDeg: Double(i) * 90)
                let letter = Self.label(names[i], at: dir * radius,
                                        color: UIColor.white, size: 0.12, spacing: 0, weight: .ultraLight)
                letter.opacity = 0.45
                skyRoot.addChildNode(letter)
            }
            let ring = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.02)
            ring.materials = [Self.glowMaterial(.white, opacity: 0.15)]
            skyRoot.addChildNode(SCNNode(geometry: ring))
        }

        /// Discovered constellations get golden strands.
        func refreshDiscoveredColors() {
            for i in 0..<drawn.count {
                let gold = discovered.contains(drawn[i].placed.name)
                let color = gold ? Self.discoveredCore : Self.lineCore
                drawn[i].core.diffuse.contents = color.withAlphaComponent(gold ? 0.8 : 0.55)
            }
        }

        // MARK: - Discovering: hold on a constellation

        private func updateDwell(dt: Double) {
            guard let camera = view?.pointOfView else { return }
            let forward = camera.simdWorldFront

            // closest undiscovered constellation near the middle of the screen
            var target: DrawnConstellation?
            var bestAngle = dwellAngle
            for i in 0..<drawn.count {
                let d = drawn[i]
                guard !discovered.contains(d.placed.name), d.placed.centerAlt > -5 else { continue }
                let angle = acos(max(-1, min(1, simd_dot(forward, d.center))))
                if angle < bestAngle {
                    bestAngle = angle
                    target = d
                }
            }

            guard let target else {
                if dwellName != nil {
                    dwellName = nil
                    dwellTime = 0
                    lastReported = -1
                    onDwell(nil, 0)
                }
                return
            }

            if target.placed.name != dwellName {
                dwellName = target.placed.name
                dwellTime = 0
            }
            dwellTime += dt
            let progress = min(1, dwellTime / dwellNeeded)
            if abs(progress - lastReported) >= 0.04 || progress >= 1 {
                lastReported = progress
                onDwell(target.placed.name, progress)
            }

            if progress >= 1 {
                discovered.insert(target.placed.name)
                refreshDiscoveredColors()
                celebrate(at: target.center)
                dwellName = nil
                dwellTime = 0
                lastReported = -1
                onDwell(nil, 0)
                onDiscover(target.placed)
            }
        }

        /// Expanding golden ring where a constellation was just discovered.
        private func celebrate(at direction: SIMD3<Float>) {
            let ring = SCNTorus(ringRadius: 1.0, pipeRadius: 0.06)
            ring.materials = [Self.glowMaterial(Self.discoveredCore, opacity: 1)]
            let node = SCNNode(geometry: ring)
            node.simdPosition = direction * (radius * 0.95)
            // face the viewer: the torus lies flat in its x-z plane, so tilt it toward the centre
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: -direction)
            skyRoot.addChildNode(node)
            node.runAction(.sequence([
                .group([.scale(to: 6, duration: 0.9), .fadeOut(duration: 0.9)]),
                .removeFromParentNode()
            ]))
        }

        // MARK: - Focus: light up what you're pointing at

        private func updateFocus() {
            guard let camera = view?.pointOfView else { return }
            let forward = camera.simdWorldFront

            for i in 0..<drawn.count {
                let d = drawn[i]
                // 1 when dead centre, 0 when ~35° or more away
                let angle = acos(max(-1, min(1, simd_dot(forward, d.center))))
                let t = max(0, min(1, 1 - angle / (35 * .pi / 180)))
                let focus = CGFloat(t * t * (3 - 2 * t))  // smoothstep

                d.lines.opacity = 0.3 + 0.7 * focus
                d.stars.opacity = 0.65 + 0.35 * focus
                d.label.opacity = 0.12 + 0.78 * focus
                // the illustration only appears when you're pointing right at it (within ~12°)
                let a = max(0, min(1, 1 - angle / (12 * .pi / 180)))
                d.art?.opacity = CGFloat(a * a * (3 - 2 * a)) * 0.55
            }
        }

        // MARK: - Illustration mesh

        /// A (grid+1)×(grid+1) mesh whose corners sit on the sky, textured with the illustration.
        private static func artMesh(grid: Int, directions: [SIMD3<Float>], radius: Float,
                                    image: UIImage) -> SCNNode {
            var vertices: [SCNVector3] = []
            var uvs: [CGPoint] = []
            for j in 0...grid {
                for i in 0...grid {
                    let p = directions[j * (grid + 1) + i] * radius
                    vertices.append(SCNVector3(p.x, p.y, p.z))
                    uvs.append(CGPoint(x: Double(i) / Double(grid), y: Double(j) / Double(grid)))
                }
            }
            var indices: [Int32] = []
            for j in 0..<grid {
                for i in 0..<grid {
                    let a = Int32(j * (grid + 1) + i), b = a + 1
                    let c = a + Int32(grid + 1), d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uvs)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])

            let m = SCNMaterial()
            m.diffuse.contents = image
            m.multiply.contents = UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1)  // cool moonlit tint
            m.lightingModel = .constant
            m.blendMode = .add            // black background disappears, art glows into the sky
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            geometry.materials = [m]

            let node = SCNNode(geometry: geometry)
            node.opacity = 0
            return node
        }

        // MARK: - Real stars

        /// Thousands of real stars, brighter = bigger. Bright named stars get small labels.
        private func buildStarField(_ stars: [PlacedStar], named: [PlacedNamedStar]) {
            let old = starFieldRoot.childNodes
            for i in 0..<old.count { old[i].removeFromParentNode() }

            // magnitude buckets: (faintest magnitude in bucket, point size in pixels, brightness)
            let buckets: [(Double, CGFloat, CGFloat)] = [
                (1.0, 7, 1.0), (2.0, 5, 0.95), (3.0, 3.6, 0.85), (4.0, 2.6, 0.7), (5.0, 1.9, 0.55), (9, 1.4, 0.4)
            ]
            let dim: CGFloat = useAR ? 0.6 : 1.0   // real sky is already behind the camera view
            var lower = -10.0
            for b in 0..<buckets.count {
                var verts: [SCNVector3] = []
                for i in 0..<stars.count where stars[i].mag > lower && stars[i].mag <= buckets[b].0 {
                    let p = stars[i].direction * (radius * 1.03)
                    verts.append(SCNVector3(p.x, p.y, p.z))
                }
                lower = buckets[b].0
                guard !verts.isEmpty else { continue }

                var idx: [Int32] = []
                for i in 0..<verts.count { idx.append(Int32(i)) }
                let element = SCNGeometryElement(indices: idx, primitiveType: .point)
                element.pointSize = buckets[b].1
                element.minimumPointScreenSpaceRadius = buckets[b].1 / 2
                element.maximumPointScreenSpaceRadius = buckets[b].1 / 2
                let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [element])
                geometry.materials = [Self.glowMaterial(UIColor(white: 1, alpha: 1), opacity: buckets[b].2 * dim)]
                starFieldRoot.addChildNode(SCNNode(geometry: geometry))
            }

            // names for the brightest stars, warm like Stellarium
            for i in 0..<named.count {
                let s = named[i]
                let up = SIMD3<Float>(0, 1, 0)
                var side = simd_cross(s.direction, up)
                if simd_length(side) < 0.01 { side = SIMD3<Float>(1, 0, 0) }
                let offset = simd_normalize(side) * 0.012 + up * 0.012     // nudge label off the star
                let label = Self.label(s.name, at: simd_normalize(s.direction + offset) * (radius * 1.02),
                                       color: UIColor(red: 1.0, green: 0.78, blue: 0.5, alpha: 1),
                                       size: 0.05, spacing: 0.5, weight: .medium)
                label.opacity = 0.75
                starFieldRoot.addChildNode(label)
            }
        }

        /// Virtual sky only: dark ground so the horizon reads like the real thing.
        func addGround() {
            let disc = SCNCylinder(radius: 60, height: 0.001)
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.015, green: 0.02, blue: 0.03, alpha: 1)
            m.lightingModel = .constant
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            disc.materials = [m]
            let ground = SCNNode(geometry: disc)
            ground.position = SCNVector3(0, -0.6, 0)
            ground.renderingOrder = 100      // drawn last, hides everything below the horizon
            virtualCamera.parent?.addChildNode(ground) ?? skyRoot.addChildNode(ground)
        }

        // MARK: - Building blocks

        /// Night-sky gradient for the simulator background.
        static let nightGradient: UIImage = {
            let size = CGSize(width: 4, height: 256)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [UIColor(red: 0.01, green: 0.02, blue: 0.07, alpha: 1).cgColor,
                              UIColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 1).cgColor,
                              UIColor(red: 0.08, green: 0.08, blue: 0.20, alpha: 1).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: colors, locations: [0, 0.7, 1])!
                ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: 0, y: size.height), options: [])
            }
        }()

        /// Round glow with a faint four-point flare, generated once and shared.
        private static let sparkleImage: UIImage = {
            let s: CGFloat = 128
            let mid = CGPoint(x: s / 2, y: s / 2)
            return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
                let cg = ctx.cgContext
                // soft round glow
                let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor.white.cgColor,
                                               UIColor(white: 1, alpha: 0.35).cgColor,
                                               UIColor.clear.cgColor] as CFArray,
                                      locations: [0, 0.12, 0.5])!
                cg.drawRadialGradient(glow, startCenter: mid, startRadius: 0,
                                      endCenter: mid, endRadius: s / 2, options: [])
                // thin flare spikes
                let spike = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [UIColor.clear.cgColor,
                                                UIColor(white: 1, alpha: 0.7).cgColor,
                                                UIColor.clear.cgColor] as CFArray,
                                       locations: [0, 0.5, 1])!
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: mid.y - 1, width: s, height: 2))
                cg.drawLinearGradient(spike, start: CGPoint(x: 0, y: mid.y),
                                      end: CGPoint(x: s, y: mid.y), options: [])
                cg.restoreGState()
                cg.saveGState()
                cg.clip(to: CGRect(x: mid.x - 1, y: 0, width: 2, height: s))
                cg.drawLinearGradient(spike, start: CGPoint(x: mid.x, y: 0),
                                      end: CGPoint(x: mid.x, y: s), options: [])
                cg.restoreGState()
            }
        }()

        private static func sparkle(at position: SIMD3<Float>, size: Float, tint: UIColor,
                                    brightness: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
            let m = SCNMaterial()
            m.diffuse.contents = sparkleImage
            m.multiply.contents = tint
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
            let duration = Double.random(in: 1.2...3.0)
            let twinkle = SCNAction.sequence([.fadeOpacity(to: brightness * 0.55, duration: duration),
                                              .fadeOpacity(to: brightness, duration: duration)])
            node.runAction(.repeatForever(twinkle))
            return node
        }

        private static func label(_ text: String, at position: SIMD3<Float>, color: UIColor,
                                  size: Float, spacing: CGFloat, weight: UIFont.Weight) -> SCNNode {
            var font = UIFont.systemFont(ofSize: 10, weight: weight)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = UIFont(descriptor: rounded, size: 10)
            }
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: spacing])
            let geometry = SCNText(string: attributed, extrusionDepth: 0)
            geometry.flatness = 0.1
            geometry.materials = [glowMaterial(color, opacity: 1)]

            let text = SCNNode(geometry: geometry)
            let (minB, maxB) = text.boundingBox
            text.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
            text.scale = SCNVector3(size, size, size)

            let holder = SCNNode()
            holder.simdPosition = position
            holder.addChildNode(text)
            holder.constraints = [SCNBillboardConstraint()]
            return holder
        }

        /// Additive, unlit material: things glow and blend into the sky/camera instead of sitting on top.
        private static func glowMaterial(_ color: UIColor, opacity: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color.withAlphaComponent(opacity)
            m.lightingModel = .constant
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false  // never hidden behind real-world things
            return m
        }

        /// A thin cylinder between two points.
        private static func strand(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat,
                                   material: SCNMaterial) -> SCNNode {
            let v = b - a
            let length = simd_length(v)
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(max(length, 0.01)))
            cylinder.radialSegmentCount = 8
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
            yaw += Float(t.x) * 0.0022
            pitch = min(1.5, max(-0.3, pitch + Float(t.y) * 0.0022))
            updateVirtualCamera()
        }

        private func updateVirtualCamera() {
            virtualCamera.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        // MARK: - Every frame: follow the camera (AR) and update the focus glow

        func startTimer() {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }

        func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        private func tick() {
            if useAR, let camera = view?.pointOfView {
                // Stars are "infinitely" far away, so the sky moves with you.
                skyRoot.simdPosition = camera.simdWorldPosition
            }
            updateFocus()
            updateDwell(dt: 1.0 / 30.0)
        }
    }
}
