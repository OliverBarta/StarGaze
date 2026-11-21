import SwiftUI
import ARKit

/// Identifies which constellation's info sheet is open.
struct InfoTarget: Identifiable {
    let id: String
    let name: String
    let directionText: String
}

/// Main Stars tab: hold the phone up and see the constellations over the camera.
/// Tap one to learn about it. In the simulator you get a virtual sky to drag around.
struct SkyScreen: View {
    @Environment(DiscoveryStore.self) private var store
    @State private var location = LocationProvider()
    @State private var dwellName: String?
    @State private var dwellProgress = 0.0
    @State private var toast: String?
    @State private var skyHidden = false
    @State private var placed: [PlacedConstellation] = []
    @State private var stars: [PlacedStar] = []
    @State private var namedStars: [PlacedNamedStar] = []
    @State private var version = 0
    @State private var infoTarget: InfoTarget?

    // Simulators have no camera or compass, so they get the virtual sky.
    private let arSupported = ARWorldTrackingConfiguration.isSupported

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()   // what shows if the sky view is paused/hidden

            SkySceneView(
                useAR: arSupported,
                constellations: placed,
                version: version,
                discovered: Set(store.discoveries.keys),
                stars: stars,
                namedStars: namedStars,
                hidden: skyHidden,
                onTap: { c in
                    infoTarget = InfoTarget(id: c.id, name: c.name, directionText: c.directionText)
                },
                onDwell: { name, progress in
                    dwellName = name
                    dwellProgress = progress
                },
                onDiscover: { c in
                    if store.discover(c.name, place: location.placeName) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        showToast("✦ Discovered \(c.name)")
                    }
                }
            )
            .ignoresSafeArea()

            // fill-up ring while you hold on a constellation
            if let dwellName {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: dwellProgress)
                            .stroke(Color(red: 1, green: 0.8, blue: 0.4),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: dwellProgress)
                    }
                    .frame(width: 58, height: 58)
                    Text(dwellName.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .kerning(3)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            VStack {
                hint
                Spacer()
                if let toast {
                    Text(toast)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.5))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()
            .animation(.spring(response: 0.4), value: toast)
            .animation(.easeOut(duration: 0.2), value: dwellName)

            #if DEBUG
            // Testing helper: wipe discoveries so you can replay the cutscenes.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        store.resetAll()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding()
            #endif
        }
        .task {
            location.start()
            // Stars drift ~0.25° a minute, so recalculating every 30 s is plenty.
            while !Task.isCancelled {
                recalculate()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: location.latitude) { _, _ in recalculate() }
        // pause the sky while a cutscene is playing (once the cutscene has faded in over it)
        .onChange(of: store.pendingCompletions.isEmpty) { _, empty in
            if empty {
                skyHidden = false
            } else {
                Task {
                    try? await Task.sleep(for: .seconds(0.45))
                    if !store.pendingCompletions.isEmpty { skyHidden = true }
                }
            }
        }
        .sheet(item: $infoTarget) { target in
            ConstellationInfoView(name: target.name, directionText: target.directionText)
                .presentationDetents([.medium, .large])
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }

    private func recalculate() {
        let now = Date()
        placed = SkyModel.place(latDeg: location.latitude, lonDeg: location.longitude, date: now)
        stars = SkyModel.placeStars(latDeg: location.latitude, lonDeg: location.longitude, date: now)
        namedStars = SkyModel.placeNamedStars(latDeg: location.latitude, lonDeg: location.longitude, date: now)
        version += 1
    }

    private var hint: some View {
        VStack(spacing: 2) {
            Text(arSupported ? "Point your phone at the sky" : "Drag to look around the sky")
                .font(.subheadline.weight(.semibold))
            Text("Hold on a constellation to discover it · tap to learn more"
                 + (location.usingFallback ? " · sky over London, ON" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Sheet with Gemini's description of a constellation.
struct ConstellationInfoView: View {
    let name: String
    let directionText: String
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.largeTitle.bold())
                Label(directionText, systemImage: "location.north.line")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let text {
                    Text(text)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else {
                    SwiftUI.ProgressView("Asking Gemini…")
                }

                Text("Constellation illustrations by Johan Meuris (Free Art License), via Stellarium.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .task {
            do {
                text = try await GeminiService().describe(constellation: name)
            } catch {
                errorMessage = "Couldn't load info: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    SkyScreen()
        .environment(DiscoveryStore())
}
