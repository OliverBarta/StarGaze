import SwiftUI

/// Full-screen "set complete" cutscene in the style of Sol's RNG:
/// 1. ROLL   – names flick past with "1 in X" odds, slow down and land on your find
/// 2. RUN    – your constellation's creature charges across the screen
/// 3. VORTEX – the set's other creatures appear, the runner is pulled in, they spin together
/// 4. REVEAL – white flash, star burst, the set name + odds, creatures floating above
struct SetCutsceneView: View {
    let completion: DiscoveryStore.Completion
    let onFinish: () -> Void

    private var set: ConstellationSet { completion.set }
    private var hero: String { completion.names.first ?? "" }

    // backdrop
    @State private var darkness = 0.0
    // 1. roll
    @State private var rollVisible = false
    @State private var rollText = ""
    @State private var rollOdds = ""
    @State private var rollColor = Color.white
    @State private var rollScale: CGFloat = 1
    // 2. run
    @State private var runnerVisible = false
    @State private var runnerPos = CGSize.zero
    @State private var runnerScale: CGFloat = 1
    @State private var hop = false
    // 3. vortex
    @State private var othersVisible = false
    @State private var heroInOrbit = false
    @State private var figureRadiusFactor: CGFloat = 1
    @State private var figureAngle: Double = 0
    @State private var figureScale: CGFloat = 1
    @State private var vortexGlow: CGFloat = 0
    @State private var shakeProgress: CGFloat = 0
    @State private var shakeStrength: CGFloat = 0
    // 4. reveal
    @State private var flash = 0.0
    @State private var particlesOn = false
    @State private var burst = false
    @State private var showTitle = false
    @State private var tableauIn = false
    @State private var bob = false
    @State private var shimmer = false
    @State private var canDismiss = false
    @State private var finished = false

    @State private var particles: [Particle] = (0..<70).map { _ in Particle() }

    struct Particle: Identifiable {
        let id = UUID()
        let angle = Double.random(in: 0..<(2 * .pi))
        let distance = CGFloat.random(in: 120...460)
        let size = CGFloat.random(in: 2...5)
        let delay = Double.random(in: 0...0.2)
    }

    var body: some View {
        GeometryReader { geo in
            stage(size: geo.size)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if canDismiss { finish() } }
        .task { await play() }
    }

    private func stage(size: CGSize) -> some View {
        let orbit: CGFloat = min(size.width, size.height) * 0.32
        return ZStack {
            backdrop(size: size)
            vortex(size: size)
            orbitFigures(orbit: orbit)
            if runnerVisible { runner }
            if rollVisible { roll }
            particleBurst
            if showTitle {
                titleCard
                    .transition(.scale(scale: 1.8).combined(with: .opacity))
            }
            Color.white.opacity(flash).allowsHitTesting(false)
        }
        .modifier(ShakeEffect(progress: shakeProgress, strength: shakeStrength, building: true))
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Layers

    private func backdrop(size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(darkness)
            RadialGradient(colors: [set.color.opacity(0.28), Color.clear],
                           center: .center, startRadius: 0, endRadius: size.height * 0.6)
                .opacity(darkness)
            DriftingStars(color: set.color)
                .opacity(darkness)
        }
    }

    /// Glowing core the creatures get sucked into.
    private func vortex(size: CGSize) -> some View {
        RadialGradient(colors: [Color.white, set.color.opacity(0.7), Color.clear],
                       center: .center, startRadius: 0, endRadius: 90)
            .frame(width: 180, height: 180)
            .scaleEffect(vortexGlow)
            .opacity(Double(min(1, vortexGlow)))
            .blendMode(.plusLighter)
    }

    /// 1. The "rolling" text.
    private var roll: some View {
        VStack(spacing: 6) {
            Text(rollText)
                .font(.system(size: 40, weight: .black, design: .serif))
                .foregroundStyle(rollColor)
                .shadow(color: rollColor.opacity(0.9), radius: 14)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(rollOdds)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .scaleEffect(rollScale)
        .padding(.horizontal, 24)
    }

    /// 2. The hero creature charging across, with motion-blur ghosts behind it.
    /// Creatures with a run cycle (e.g. the lynx) actually run; the rest bound along.
    private var runner: some View {
        let animated = RunAnimation.hasFrames(for: hero)
        let hopAmount: CGFloat = animated ? 0.2 : 1
        return ZStack {
            ForEach((0..<4).reversed(), id: \.self) { k in
                RunnerSprite(name: hero, color: set.color)
                    .frame(width: 210, height: 210)
                    .offset(x: -CGFloat(k) * 36)
                    .opacity(k == 0 ? 1 : 0.4 / Double(k))
            }
        }
        // bounding gait
        .scaleEffect(x: 1 + (hop ? -0.04 : 0.04) * hopAmount, y: 1 + (hop ? 0.06 : -0.06) * hopAmount,
                     anchor: .bottom)
        .rotationEffect(.degrees((hop ? -5 : 4) * Double(hopAmount)))
        .offset(y: (hop ? -30 : 6) * hopAmount)
        .animation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true), value: hop)
        .scaleEffect(runnerScale)
        .offset(runnerPos)
    }

    /// 3. The set's creatures orbiting, then spiralling into the core.
    private func orbitFigures(orbit: CGFloat) -> some View {
        ZStack {
            ForEach(0..<completion.names.count, id: \.self) { i in
                orbitFigure(index: i, orbit: orbit)
            }
        }
    }

    private func orbitFigure(index i: Int, orbit: CGFloat) -> some View {
        let count = Double(completion.names.count)
        let start: Double = Double(i) / count * 2 * Double.pi - Double.pi / 2   // slot 0 = top
        let radius: CGFloat = orbit * figureRadiusFactor
        let visible: Bool = i == 0 ? heroInOrbit : othersVisible
        return ConstellationFigure(name: completion.names[i], color: set.color,
                                   showName: false, showLines: false)
            .frame(width: 150, height: 150)
            .scaleEffect(figureScale)
            .modifier(OrbitEffect(radius: radius, angle: start + figureAngle))
            .opacity(visible ? 1 : 0)
    }

    /// 4. Stars bursting out of the flash.
    private var particleBurst: some View {
        ZStack {
            ForEach(particles) { p in
                particle(p)
            }
        }
        .drawingGroup()
    }

    private func particle(_ p: Particle) -> some View {
        let dx: CGFloat = burst ? CGFloat(cos(p.angle)) * p.distance : 0
        let dy: CGFloat = burst ? CGFloat(sin(p.angle)) * p.distance : 0
        let opacity: Double = burst ? 0 : (particlesOn ? 1 : 0)
        return Image(systemName: "sparkle")
            .font(.system(size: p.size * 2.4))
            .foregroundStyle(Color.white)
            .offset(x: dx, y: dy)
            .opacity(opacity)
            .animation(.easeOut(duration: 1.4).delay(p.delay), value: burst)
    }

    /// 4. Sol's RNG-style reveal.
    private var titleCard: some View {
        VStack(spacing: 8) {
            tableau
                .padding(.bottom, 6)

            Text(set.tier)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .kerning(10)
                .foregroundStyle(set.color)
                .shadow(color: set.color, radius: 10)

            shinyTitle

            Text(set.odds)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: set.color, radius: 10)

            Text(set.tagline)
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 2)

            Text(canDismiss ? "Tap to continue" : " ")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 22)
        }
        .padding(.horizontal, 20)
    }

    private var titleText: some View {
        Text(set.title)
            .font(.system(size: 44, weight: .black, design: .serif))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .lineLimit(2)
    }

    /// Set name with a light sweep running across it.
    private var shinyTitle: some View {
        titleText
            .foregroundStyle(LinearGradient(colors: [.white, set.color], startPoint: .top, endPoint: .bottom))
            .shadow(color: set.color.opacity(0.9), radius: 18)
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.95), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.3)
                        .offset(x: shimmer ? g.size.width : -g.size.width * 0.3)
                }
                .mask(titleText)
            }
    }

    /// The creatures, gathered and floating above the title.
    private var tableau: some View {
        let count = completion.names.count
        return HStack(alignment: .center, spacing: -16) {
            ForEach(0..<count, id: \.self) { i in
                tableauCreature(index: i, count: count)
            }
        }
        .frame(height: 190)
    }

    private func tableauCreature(index i: Int, count: Int) -> some View {
        let middle = Double(count - 1) / 2
        let distance = abs(Double(i) - middle)
        let lift: CGFloat = CGFloat(distance * distance) * 10 - 30
        let size: CGFloat = i == 0 ? 108 : 90
        return ConstellationFigure(name: completion.names[i], color: set.color,
                                   showName: true, showLines: false)
            .frame(width: size, height: size)
            .offset(y: lift + (bob ? -5 : 5))
            .scaleEffect(tableauIn ? 1 : 0.1)
            .opacity(tableauIn ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.58).delay(Double(i) * 0.08), value: tableauIn)
            .animation(.easeInOut(duration: 1.5 + Double(i) * 0.25).repeatForever(autoreverses: true), value: bob)
            .zIndex(i == 0 ? 1 : 0)
    }

    // MARK: - Timeline

    private func play() async {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let light = UIImpactFeedbackGenerator(style: .light)
        let size = UIScreen.main.bounds.size
        let orbit = min(size.width, size.height) * 0.32

        // fade to black
        withAnimation(.easeIn(duration: 0.35)) { darkness = 0.95 }
        await pause(0.35)

        // 1. ROLL — names flick past, slowing down, landing on the find
        let pool = SkyCatalog.constellations.map(\.name)
        let colors = ConstellationSet.all.map(\.color) + [Color.white, Color.gray]
        rollVisible = true
        var interval = 0.045
        for _ in 0..<24 {
            rollText = pool.randomElement() ?? hero
            rollColor = colors.randomElement() ?? .white
            rollOdds = "1 in \(Int.random(in: 2...99_999).formatted())"
            light.impactOccurred(intensity: 0.5)
            await pause(interval)
            interval *= 1.1
        }
        rollText = hero
        rollColor = set.color
        rollOdds = set.odds
        heavy.impactOccurred()
        rollScale = 1.35
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { rollScale = 1 }
        await pause(0.9)
        withAnimation(.easeOut(duration: 0.25)) { rollVisible = false }

        // 2. RUN — the creature charges in from the left
        runnerPos = CGSize(width: -size.width * 0.85, height: 60)
        runnerVisible = true
        hop = true
        withAnimation(.linear(duration: 2.0)) {
            runnerPos = CGSize(width: size.width * 0.12, height: 60)
        }
        for _ in 0..<12 {   // footsteps
            light.impactOccurred(intensity: 0.6)
            await pause(0.17)
        }

        // 3. VORTEX — the others appear, the runner is yanked into the circle
        withAnimation(.easeOut(duration: 0.5)) {
            othersVisible = true
            vortexGlow = 0.6
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            runnerPos = CGSize(width: 0, height: -orbit)
            runnerScale = 150.0 / 210.0
        }
        await pause(0.45)
        hop = false
        heroInOrbit = true
        runnerVisible = false

        // spin...
        withAnimation(.easeInOut(duration: 0.9)) { figureAngle = .pi * 0.9 }
        await pause(0.7)
        // ...and spiral in, shaking harder and harder
        withAnimation(.easeIn(duration: 1.3)) {
            figureRadiusFactor = 0
            figureAngle = .pi * 0.9 + 2.4 * .pi
            figureScale = 0.2
            vortexGlow = 1.6
        }
        shakeStrength = 10
        withAnimation(.linear(duration: 1.3)) { shakeProgress = 1 }   // builds up smoothly
        for step in 0..<13 {
            light.impactOccurred(intensity: 0.3 + CGFloat(step) * 0.05)
            await pause(0.1)
        }
        shakeStrength = 0

        // 4. FLASH + REVEAL
        heavy.impactOccurred(intensity: 1)
        othersVisible = false
        heroInOrbit = false
        vortexGlow = 0
        flash = 1
        withAnimation(.easeOut(duration: 1.0)) { flash = 0 }
        particlesOn = true
        await pause(0.03)
        burst = true
        await pause(0.1)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { showTitle = true }
        tableauIn = true
        bob = true
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false).delay(0.5)) { shimmer = true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        await pause(1.4)
        withAnimation { canDismiss = true }
        await pause(4.0)
        finish()
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Run-cycle frames shipped in Data/Art as "<name>-run-0.jpg", "<name>-run-1.jpg", …
enum RunAnimation {
    private static var cache: [String: [UIImage]] = [:]

    static func frames(for name: String) -> [UIImage] {
        if let cached = cache[name] { return cached }
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        var result: [UIImage] = []
        for i in 0..<60 {
            guard let url = Bundle.main.url(forResource: "\(slug)-run-\(i)", withExtension: "jpg"),
                  let image = UIImage(contentsOfFile: url.path) else { break }
            result.append(image)
        }
        cache[name] = result
        return result
    }

    static func hasFrames(for name: String) -> Bool { !frames(for: name).isEmpty }
}

/// The running creature: plays its run cycle like a flipbook if it has one,
/// otherwise shows the still illustration.
struct RunnerSprite: View {
    let name: String
    let color: Color
    var frameDuration = 0.065

    var body: some View {
        let frames = RunAnimation.frames(for: name)
        if frames.isEmpty {
            ConstellationFigure(name: name, color: color, showName: false, showLines: false)
        } else {
            TimelineView(.periodic(from: .now, by: frameDuration)) { timeline in
                let index = Int(timeline.date.timeIntervalSinceReferenceDate / frameDuration) % frames.count
                color.mix(with: .white, by: 0.45)
                    .mask {
                        Image(uiImage: frames[index])
                            .resizable()
                            .scaledToFit()
                            .luminanceToAlpha()
                    }
                    .shadow(color: color.opacity(0.8), radius: 12)
                    .drawingGroup()
            }
        }
    }
}

/// Slow-drifting background stars for the cutscene.
struct DriftingStars: View {
    let color: Color
    @State private var seeds: [(x: Double, y: Double, speed: Double, size: Double)] =
        (0..<70).map { _ in (.random(in: 0...1), .random(in: 0...1), .random(in: 0.01...0.05), .random(in: 0.8...2.4)) }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<seeds.count {
                    let s = seeds[i]
                    let y = (s.y - t * s.speed).truncatingRemainder(dividingBy: 1)
                    let point = CGPoint(x: s.x * size.width, y: (y < 0 ? y + 1 : y) * size.height)
                    let twinkle = 0.5 + 0.5 * sin(t * 2 + Double(i))
                    let r = s.size
                    context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                                 with: .color(i % 3 == 0 ? color.opacity(0.8 * twinkle) : .white.opacity(0.7 * twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Places a view on a circle; animating radius + angle together makes it travel along a spiral.
struct OrbitEffect: GeometryEffect {
    var radius: CGFloat
    var angle: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(radius, angle) }
        set { radius = newValue.first; angle = newValue.second }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: radius * cos(angle),
                                              y: radius * sin(angle)))
    }
}

/// A constellation's mythological creature (if it has one) with its glowing stick figure on top,
/// both drawn from real star positions so they line up.
struct ConstellationFigure: View {
    let name: String
    let color: Color
    var showName = true
    var showLines = true

    var body: some View {
        let art = SkyArt.entry(forName: name)
        // Turn the creature upright (on the sky it's tilted), and scale up to use the freed space.
        let angle = art.map { atan2($0.affine[1], $0.affine[0]) } ?? 0
        let fill = abs(cos(angle)) + abs(sin(angle))
        VStack(spacing: 2) {
            ZStack {
                if let art, let image = SkyArt.image(named: art.file) {
                    // glowing creature: the picture's brightness becomes its transparency,
                    // so its black background disappears
                    color.mix(with: .white, by: 0.45)
                        .mask {
                            artCanvas(art: art, image: image).luminanceToAlpha()
                        }
                        .shadow(color: color.opacity(0.8), radius: 12)
                        .drawingGroup()
                }
                if showLines || art == nil {
                    lines(art: art)
                }
            }
            .rotationEffect(.radians(-angle))
            .scaleEffect(fill)

            if showName {
                Text(name.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
            }
        }
    }

    private func artCanvas(art: ArtEntry, image: UIImage) -> some View {
        Canvas { context, size in
            let half = min(size.width, size.height) / 2
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let f = art.affine
            context.concatenate(CGAffineTransform(
                a: half * f[0], b: half * f[1], c: half * f[2], d: half * f[3],
                tx: mid.x + half * f[4], ty: mid.y + half * f[5]))
            context.draw(Image(uiImage: image),
                         in: CGRect(x: 0, y: 0, width: art.size[0], height: art.size[1]))
        }
    }

    private func lines(art: ArtEntry?) -> some View {
        // Use the art's stick figure (same scale as the picture) when there is one
        var segs: [[CGPoint]] = []
        if let art {
            for s in 0..<art.lines.count {
                var seg: [CGPoint] = []
                for p in 0..<art.lines[s].count {
                    seg.append(CGPoint(x: art.lines[s][p][0], y: art.lines[s][p][1]))
                }
                segs.append(seg)
            }
        } else {
            segs = ConstellationShape.segments(for: name)
        }

        return Canvas { context, size in
            let half = min(size.width, size.height) / 2
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            var path = Path()
            var stars: [CGPoint] = []
            for s in 0..<segs.count {
                for p in 0..<segs[s].count {
                    let pt = CGPoint(x: mid.x + segs[s][p].x * half, y: mid.y + segs[s][p].y * half)
                    if p == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    stars.append(pt)
                }
            }
            context.stroke(path, with: .color(color.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            for i in 0..<stars.count {
                let r: CGFloat = 2.2
                context.fill(Path(ellipseIn: CGRect(x: stars[i].x - r, y: stars[i].y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(.white))
            }
        }
        .shadow(color: color, radius: 6)
    }
}


#Preview {
    SetCutsceneView(
        completion: .init(set: ConstellationSet.all[0],
                          names: ["Leo", "Ursa Major", "Pegasus", "Cygnus", "Taurus"]),
        onFinish: {})
}
