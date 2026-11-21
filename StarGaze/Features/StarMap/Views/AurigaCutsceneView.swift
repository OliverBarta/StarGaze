import SwiftUI

/// Auriga's special cutscene (no text): a giant crystal pillar sweeps in, a star ignites at its tip
/// and flares with long light streaks and rainbow lens rings, the crystal pulls away into a shard,
/// one last blinding flare – and the Charioteer appears.
/// An original effect in the spirit of Sol's RNG's crystal cutscenes.
struct AurigaCutsceneView: View {
    let completion: DiscoveryStore.Completion
    let onFinish: () -> Void

    private let tint = Color(red: 0.78, green: 0.75, blue: 1.0)   // pale lavender

    @State private var darkness = 0.0
    @State private var bars: CGFloat = 0                // letterbox, 0...1
    @State private var pillarIn = false
    @State private var pillarShard = false              // zoomed-out "shard" stage
    @State private var pillarOpacity = 1.0
    @State private var shine = false
    @State private var flareScale: CGFloat = 0
    @State private var flareSpin = 0.0
    @State private var flareOpacity = 1.0
    @State private var rings: CGFloat = 0.2
    @State private var ringOpacity = 0.0
    @State private var flash = 0.0
    @State private var shakeProgress: CGFloat = 0
    @State private var shakeStrength: CGFloat = 0
    @State private var aura = false
    @State private var nameIn = false
    @State private var nameShine = false
    @State private var heroIn = false
    @State private var float = false
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // where the star sits: the lower tip of the pillar
            let flarePoint = pillarShard ? CGSize(width: -w * 0.12, height: h * 0.06)
                                         : CGSize(width: -w * 0.22, height: h * 0.2)
            ZStack {
                Color.black.opacity(darkness)

                // the crystal pillar
                // After the pull-back it becomes a thin beam that still runs from the star
                // all the way off the top-right of the screen.
                // centred on the star and long enough to run off both ends of the screen
                let shardCenter = flarePoint
                CrystalPillar(tint: tint, shine: shine)
                    .frame(width: w * 0.55, height: h * 1.5)
                    .scaleEffect(x: pillarShard ? 0.28 : 1, y: pillarShard ? 2.0 : 1)
                    .rotationEffect(.degrees(pillarShard ? 32 : 24))
                    .offset(pillarIn
                            ? (pillarShard ? shardCenter : CGSize(width: w * 0.18, height: -h * 0.05))
                            : CGSize(width: w * 1.2, height: -h * 0.9))
                    .opacity(pillarOpacity)

                // rainbow lens rings
                ForEach(0..<3, id: \.self) { i in
                    LensRing(lineWidth: CGFloat(10 - i * 3))
                        .frame(width: w * (0.9 + CGFloat(i) * 0.45), height: w * (0.9 + CGFloat(i) * 0.45))
                        .scaleEffect(rings)
                        .opacity(ringOpacity * (1 - Double(i) * 0.25))
                        .offset(flarePoint)
                }

                // the star flare
                StarFlare(tint: tint)
                    .frame(width: w * 1.6, height: w * 1.6)
                    .rotationEffect(.degrees(flareSpin))
                    .scaleEffect(flareScale)
                    .opacity(flareOpacity)
                    .offset(heroIn ? CGSize(width: 0, height: -h * 0.18) : flarePoint)

                // soft pulsing aura behind the Charioteer
                RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0.18), .clear],
                               center: .center, startRadius: 0, endRadius: w * 0.55)
                    .frame(width: w * 1.1, height: w * 1.1)
                    .scaleEffect(aura ? 1.08 : 0.9)
                    .opacity(heroIn ? 1 : 0)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)

                // the Charioteer
                ConstellationFigure(name: "Auriga", color: tint, showName: false, showLines: false)
                    .frame(width: w * 0.85, height: w * 0.85)
                    .offset(y: float ? -8 : 8)
                    .scaleEffect(heroIn ? 1 : 0.4)
                    .opacity(heroIn ? 1 : 0)

                // name
                VStack(spacing: 6) {
                    Text("AURIGA")
                        .font(.system(size: 46, weight: .black, design: .serif))
                        .kerning(8)
                        .foregroundStyle(LinearGradient(colors: [.white, tint], startPoint: .top, endPoint: .bottom))
                        .shadow(color: tint, radius: 16)
                        .overlay {
                            GeometryReader { g in
                                LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: g.size.width * 0.3)
                                    .offset(x: nameShine ? g.size.width : -g.size.width * 0.3)
                            }
                            .mask(Text("AURIGA").font(.system(size: 46, weight: .black, design: .serif)).kerning(8))
                        }
                    Text("The Charioteer")
                        .font(.system(.title3, design: .serif).italic())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .offset(y: h * 0.3)
                .opacity(nameIn ? 1 : 0)
                .scaleEffect(nameIn ? 1 : 1.3)
                .blur(radius: nameIn ? 0 : 8)

                Color.white.opacity(flash)

                // letterbox bars
                VStack {
                    Color.black.frame(height: h * 0.12 * bars)
                    Spacer()
                    Color.black.frame(height: h * 0.12 * bars)
                }
            }
            .modifier(ShakeEffect(progress: shakeProgress, strength: shakeStrength))
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if heroIn { finish() } }
        .task { await play() }
    }

    private func play() async {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let light = UIImpactFeedbackGenerator(style: .light)

        withAnimation(.easeIn(duration: 0.6)) { darkness = 1 }
        withAnimation(.easeOut(duration: 0.9)) { bars = 1 }
        await pause(0.7)

        // crystal sweeps in, slowly
        withAnimation(.easeOut(duration: 1.4)) { pillarIn = true }
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { shine = true }
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) { flareSpin = 360 }
        await pause(1.6)

        // a spark ignites at its tip and grows
        light.impactOccurred()
        withAnimation(.easeOut(duration: 1.4)) { flareScale = 0.35 }
        await pause(1.5)

        // it flares
        heavy.impactOccurred()
        withAnimation(.easeOut(duration: 0.6)) { flareScale = 0.9 }
        ringOpacity = 0.8
        withAnimation(.easeOut(duration: 2.0)) { rings = 1.2; ringOpacity = 0.35 }
        await shakeFor(duration: 0.6, strength: 7)
        await pause(0.6)

        // pull back: the crystal thins into a beam running through the star
        withAnimation(.easeInOut(duration: 1.8)) {
            pillarShard = true
            flareScale = 0.5
            rings = 0.7
        }
        await pause(2.0)

        // final blinding flare
        heavy.impactOccurred(intensity: 1)
        withAnimation(.easeIn(duration: 0.6)) { flareScale = 2.4; ringOpacity = 0.8; rings = 1.6 }
        await shakeFor(duration: 0.55, strength: 11)
        flash = 1
        pillarOpacity = 0
        withAnimation(.easeOut(duration: 1.8)) {
            flash = 0
            flareScale = 0.45          // settles into a small star behind the Charioteer's head
            flareOpacity = 0.55
            ringOpacity = 0.2
        }

        // the Charioteer appears
        withAnimation(.spring(response: 1.1, dampingFraction: 0.7)) { heroIn = true }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { aura = true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await pause(1.0)

        // ...and his name
        withAnimation(.easeOut(duration: 1.2)) { nameIn = true }
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false).delay(1.0)) { nameShine = true }

        await pause(6.0)
        finish()
    }

    private func shakeFor(duration: Double, strength: CGFloat) async {
        shakeStrength = strength
        withAnimation(.linear(duration: duration)) { shakeProgress = floor(shakeProgress) + 1 }
        await pause(duration)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.4)) { darkness = 0; bars = 0 }
        onFinish()
    }
}

/// A tall glassy prism: bright facets, a dark core and a highlight sweeping along it.
struct CrystalPillar: View {
    let tint: Color
    let shine: Bool

    var body: some View {
        ZStack {
            // facets across the width
            LinearGradient(stops: [
                .init(color: .white.opacity(0.95), location: 0.00),
                .init(color: tint.opacity(0.55), location: 0.08),
                .init(color: .white.opacity(0.85), location: 0.16),
                .init(color: Color(white: 0.15), location: 0.28),
                .init(color: tint.opacity(0.7), location: 0.40),
                .init(color: .white.opacity(0.9), location: 0.47),
                .init(color: Color(white: 0.1), location: 0.58),
                .init(color: tint.opacity(0.5), location: 0.70),
                .init(color: .white.opacity(0.95), location: 0.80),
                .init(color: tint.opacity(0.35), location: 0.90),
                .init(color: .white.opacity(0.8), location: 1.00),
            ], startPoint: .leading, endPoint: .trailing)

            // fine streaks along the length
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .white.opacity(0.25), location: 0.3),
                .init(color: .clear, location: 0.33),
                .init(color: .white.opacity(0.2), location: 0.62),
                .init(color: .clear, location: 0.66),
            ], startPoint: .top, endPoint: .bottom)
                .blendMode(.plusLighter)

            // moving highlight
            GeometryReader { g in
                LinearGradient(colors: [.clear, .white.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: g.size.height * 0.25)
                    .offset(y: shine ? g.size.height : -g.size.height * 0.25)
            }
            .blendMode(.plusLighter)
        }
        .mask(LinearGradient(colors: [.clear, .white, .white, .white, .clear],
                             startPoint: .top, endPoint: .bottom))
        .drawingGroup()
    }
}

/// Bright star core with long thin light streaks and a wide horizontal lens streak.
struct StarFlare: View {
    let tint: Color

    var body: some View {
        ZStack {
            // long streaks
            ForEach(0..<14, id: \.self) { i in
                let long = i % 2 == 0
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(long ? 0.95 : 0.6), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: long ? 3 : 1.5)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: long ? 1 : 0.55)
                    .rotationEffect(.degrees(Double(i) * 360 / 14 + (i % 3 == 0 ? 7 : 0)))
            }
            // anamorphic lens streak
            Capsule()
                .fill(LinearGradient(colors: [.clear, tint.opacity(0.8), .white, tint.opacity(0.8), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 4)
            // glowing core
            RadialGradient(colors: [.white, .white, tint.opacity(0.8), tint.opacity(0.25), .clear],
                           center: .center, startRadius: 0, endRadius: 140)
                .frame(width: 280, height: 280)
        }
        .drawingGroup()
        .blendMode(.plusLighter)
    }
}

/// A thin rainbow ring, like light splitting through a lens.
struct LensRing: View {
    var lineWidth: CGFloat = 8

    private static let rainbow: [Color] = {
        let base: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]
        var result: [Color] = []
        for i in 0..<base.count { result.append(base[i].opacity(0.5)) }
        return result
    }()

    var body: some View {
        ZStack {
            Circle()
                .stroke(AngularGradient(colors: Self.rainbow, center: .center), lineWidth: lineWidth * 2.4)
                .opacity(0.35)
            Circle()
                .stroke(AngularGradient(colors: Self.rainbow, center: .center), lineWidth: lineWidth * 0.7)
        }
        .padding(lineWidth * 1.5)
        .drawingGroup()
        .blendMode(.plusLighter)
    }
}


/// Smooth screen shake: animate `progress` from n to n+1 and it wobbles back and forth,
/// fading out (or building up), at full frame rate.
struct ShakeEffect: GeometryEffect {
    var progress: CGFloat
    var strength: CGFloat
    var building = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = progress - floor(progress)
        let envelope = building ? t : (1 - t)
        let x = sin(progress * .pi * 14) * strength * envelope
        let y = sin(progress * .pi * 10 + 1.3) * sin(progress * .pi) * strength * 0.7 * envelope
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

#Preview {
    AurigaCutsceneView(
        completion: .init(set: ConstellationSet.all[4], names: ["Auriga"], isTest: true),
        onFinish: {})
}
