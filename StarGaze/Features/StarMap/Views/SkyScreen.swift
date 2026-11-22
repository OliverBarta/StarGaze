import SwiftUI
import ARKit

/// Identifies which constellation's info sheet is open.
struct InfoTarget: Identifiable {
    let id: String
    let name: String
    let directionText: String
}

/// Main Stars tab: hold the phone up and see the constellations over the camera.
/// Tap one to learn about it.
struct SkyScreen: View {
    @Environment(DiscoveryStore.self) private var store
    @State private var location = LocationProvider()
    @State private var target: SkyTarget?
    @State private var toast: String?
    @State private var skyHidden = false
    @State private var placed: [PlacedConstellation] = []
    @State private var stars: [PlacedStar] = []
    @State private var namedStars: [PlacedNamedStar] = []
    @State private var version = 0
    @State private var infoTarget: InfoTarget?
    @State private var captureCount = 0
    @State private var showHint = true
    @State private var photo = SkyPhotoSession()

    /// The ring is full, so the capture button is enabled.
    private var canCapture: Bool {
        guard let target else { return false }
        return !target.isCollected && target.progress >= 1 && !photo.isBusy
    }

    // Simulators have no camera or compass, so they get a virtual sky instead
    // (a silent developer fallback; the UI always assumes a phone pointed at the sky).
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
                onTarget: { target = $0 },
                captureCount: captureCount,
                arPaused: photo.arPaused,
                onDiscover: { c, camera in
                    collect(c, camera: camera)
                }
            )
            .ignoresSafeArea()

            SkyPhotoOverlay(phase: photo.phase, shutterCount: photo.shutterCount,
                            analyzing: photo.isAnalyzing, debugSummary: photo.debugSummary)

            // what you're aiming at: a fill-up ring while collecting, a seal if already collected
            if let target {
                TargetRingView(target: target)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack {
                if showHint {
                    hint.transition(.move(edge: .top).combined(with: .opacity))
                }
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
                captureButton
            }
            .padding()
            .animation(.spring(response: 0.4), value: toast)
            .animation(.easeOut(duration: 0.25), value: showHint)
            .animation(.easeOut(duration: 0.2), value: target?.name)
            .animation(.easeOut(duration: 0.2), value: canCapture)
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
        .onChange(of: store.cutsceneToPlay == nil) { _, none in
            if none {
                skyHidden = false
            } else {
                Task {
                    try? await Task.sleep(for: .seconds(0.45))
                    if store.cutsceneToPlay != nil { skyHidden = true }
                }
            }
        }
        .sheet(item: $infoTarget) { target in
            ConstellationInfoView(name: target.name, directionText: target.directionText)
                .presentationDetents([.medium, .large])
        }
    }

    /// White shutter-style button; enabled once the ring around a constellation is full.
    private var captureButton: some View {
        Button {
            captureCount += 1
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4)
                Circle().fill(.white).padding(7)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canCapture)
        .opacity(canCapture ? 1 : 0.35)
        .accessibilityLabel(canCapture ? "Capture \(target?.name ?? "")" : "Capture")
        .padding(.top, 8)
    }

    /// Collects instantly, then takes the sky photo in the background (real camera only).
    /// A set cutscene triggered by this find waits until the shutter has fired.
    private func collect(_ c: PlacedConstellation, camera: ARCameraSnapshot?) {
        let willShoot = camera != nil && SkyPhotoSession.canShoot && !photo.isBusy
        if willShoot { store.holdsCutscenes = true }
        guard store.discover(c.name, place: location.placeName) else {
            store.holdsCutscenes = false
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast("✦ Discovered \(c.name)")

        guard willShoot, let camera else { return }
        let context = SkyShotContext(constellationID: c.id, constellationName: c.name,
                                     latitude: location.latitude, longitude: location.longitude,
                                     takenAt: .now, arCamera: camera)
        photo.shoot(context) { store.holdsCutscenes = false }
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
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Point your phone at the sky")
                    .font(.subheadline.weight(.semibold))
                Text("Hold on a constellation, then capture it · tap to learn more"
                     + (location.usingFallback ? " · sky over London, ON" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                showHint = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tip")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Sheet with a constellation's description from constellation-info.json.
struct ConstellationInfoView: View {
    let name: String
    let directionText: String

    private var description: String {
        ConstellationInfoCatalog.info(for: name)?.description ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.largeTitle.bold())
                Label(directionText, systemImage: "location.north.line")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if description.isEmpty {
                    Text("No description yet.").foregroundStyle(.secondary)
                } else {
                    Text(description)
                }

                Text("Constellation illustrations by Johan Meuris (Free Art License), via Stellarium.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

#Preview {
    SkyScreen()
        .environment(DiscoveryStore())
}
