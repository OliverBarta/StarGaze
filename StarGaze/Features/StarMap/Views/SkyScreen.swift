import SwiftUI

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
    @Environment(SkyReadingStore.self) private var readings
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
    /// Toasts waiting their turn (each shows for `SkyReadingTuning.toastDuration`).
    @State private var toastQueue: [String] = []
    /// Constellations whose photo is still being checked; they can't be captured again meanwhile.
    @State private var checking: Set<String> = []
    @State private var aimedUp = true
    /// Shown where "Checking photo…" goes (demo-mode captures).
    @State private var notice: String?
    /// The compass heading is inaccurate (live camera only).
    @State private var needsCalibration = false
    @AppStorage(DemoMode.defaultsKey) private var demoMode = false

    /// The ring is full and the phone points up at the sky (or demo mode), so capture is enabled.
    private var canCapture: Bool {
        guard let target else { return false }
        return !target.isCollected && target.progress >= 1 && !photo.isBusy && !checking.contains(target.name)
            && (aimedUp || demoMode)
    }

    /// A constellation is targeted but the phone is aimed too low to count as the sky.
    private var showPointUp: Bool {
        guard let target, !target.isCollected, !demoMode, !photo.isBusy else { return false }
        return !aimedUp
    }

    // Simulators have no camera or compass, so they get a virtual sky instead
    // (a silent developer fallback; the UI always assumes a phone pointed at the sky).
    private let liveSkySupported = SkyCameraDriver.isAvailable && CameraPreviewSession.isAvailable

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()   // what shows if the sky view is paused/hidden

            SkySceneView(
                useCamera: liveSkySupported,
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
                onDiscover: { c, camera in
                    collect(c, camera: camera)
                },
                onAimedUp: { aimedUp = $0 },
                quietTargetLabel: photo.isBusy,
                allowLowAim: demoMode,
                onNeedsCalibration: { needsCalibration = $0 }
            )
            .ignoresSafeArea()

            // what you're aiming at: a fill-up ring while collecting, a seal if already collected.
            // Hidden while the photo card is up, so the two never draw over each other.
            if let target, !photo.isBusy, !checking.contains(target.name) {
                TargetRingView(target: target)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            SkyPhotoOverlay(phase: photo.phase, shutterCount: photo.shutterCount,
                            subjectName: photo.subjectName)

            VStack {
                SkyTopBar(showsInstruction: showHint, usingFallbackLocation: location.usingFallback,
                          checkingPhoto: photo.isAnalyzing, notice: notice,
                          needsCalibration: needsCalibration) {
                    showHint = false
                }
                Spacer()
                if let toast {
                    Text(toast)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showPointUp {
                    Label("Point up at the sky", systemImage: "arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .transition(.opacity)
                }
                captureButton
            }
            .padding()
            .animation(.spring(response: 0.4), value: toast)
            .animation(.easeOut(duration: 0.2), value: target?.name)
            .animation(.easeOut(duration: 0.2), value: canCapture)
            .animation(.easeOut(duration: 0.2), value: showPointUp)
            .animation(.easeOut(duration: 0.2), value: photo.isBusy)
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

    static let demoNotice = "Demo mode: indoors, so the sky wasn't scanned · collected instantly"

    /// The capture button was pressed on a ready constellation. With a camera, nothing is announced
    /// until the photo has been checked: the photo runs, "Checking photo…" shows, then `finish`
    /// collects it (or not). Without a camera (simulator, no permission) it goes straight to `finish`.
    /// In demo mode there's no photo and no Gemini: it goes straight to `finish` with a short notice.
    private func collect(_ c: PlacedConstellation, camera: SkyCameraPose?) {
        guard !store.isDiscovered(c.name), !checking.contains(c.name) else { return }
        checking.insert(c.name)
        if demoMode {
            showNotice(Self.demoNotice)
            Task { await finish(nil, name: c.name) }
            return
        }
        guard let camera, SkyPhotoSession.canShoot, !photo.isBusy else {
            Task { await finish(nil, name: c.name) }
            return
        }
        let context = SkyShotContext(constellationID: c.id, constellationName: c.name,
                                     latitude: location.latitude, longitude: location.longitude,
                                     hasLocation: !location.usingFallback, takenAt: .now, cameraPose: camera)
        photo.shoot(context) { reading in
            Task { await finish(reading, name: c.name) }
        }
    }

    /// Saves the reading, then collects the constellation (saved to Supabase, then gold, haptic,
    /// set cutscene, toast) or explains why it wasn't collected. The find stays in `checking` until
    /// the save is done, so it can't be captured twice.
    private func finish(_ reading: SkyPhotoReading?, name: String) async {
        defer { checking.remove(name) }
        if let reading { readings.add(reading) }
        switch CaptureVerdict.decide(reading, name: name) {
        case .reject(let text):
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showToast(text)
        case .collect(let text, let spotted):
            do {
                guard try await store.discover(name, place: location.placeName,
                                               level: spotted ? .spotted : .located) else { return }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast("Not collected · Couldn't save \(name). Check your connection and try again.")
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showToast(text)
            if spotted { showToast("✦ Spotted \(name) · 2× points") }
        }
    }

    /// Shows a note under the instruction for `SkyReadingTuning.toastDuration`.
    private func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: SkyReadingTuning.toastDuration)
            if notice == text { notice = nil }
        }
    }

    /// Queues a toast; each one disappears on its own after `SkyReadingTuning.toastDuration`.
    private func showToast(_ text: String) {
        toastQueue.append(text)
        guard toast == nil else { return }
        Task {
            while !toastQueue.isEmpty {
                toast = toastQueue.removeFirst()
                try? await Task.sleep(for: SkyReadingTuning.toastDuration)
            }
            toast = nil
        }
    }

    private func recalculate() {
        let now = Date()
        placed = SkyModel.place(latDeg: location.latitude, lonDeg: location.longitude, date: now)
        stars = SkyModel.placeStars(latDeg: location.latitude, lonDeg: location.longitude, date: now)
        namedStars = SkyModel.placeNamedStars(latDeg: location.latitude, lonDeg: location.longitude, date: now)
        version += 1
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
        .environment(SkyReadingStore(fileURL: nil))
}
