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
    @State private var location = LocationProvider()
    @State private var placed: [PlacedConstellation] = []
    @State private var version = 0
    @State private var infoTarget: InfoTarget?

    // Simulators have no camera or compass, so they get the virtual sky.
    private let arSupported = ARWorldTrackingConfiguration.isSupported

    var body: some View {
        ZStack {
            SkySceneView(useAR: arSupported, constellations: placed, version: version) { c in
                infoTarget = InfoTarget(id: c.id, name: c.name, directionText: c.directionText)
            }
            .ignoresSafeArea()

            VStack {
                hint
                Spacer()
            }
            .padding()
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
        .sheet(item: $infoTarget) { target in
            ConstellationInfoView(name: target.name, directionText: target.directionText)
                .presentationDetents([.medium, .large])
        }
    }

    private func recalculate() {
        placed = SkyModel.place(latDeg: location.latitude, lonDeg: location.longitude, date: Date())
        version += 1
    }

    private var hint: some View {
        VStack(spacing: 2) {
            Text(arSupported ? "Point your phone at the sky" : "Drag to look around the sky")
                .font(.subheadline.weight(.semibold))
            Text("Tap a constellation to learn about it"
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
                    ProgressView("Asking Gemini…")
                }
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
}
