import SwiftUI

/// "Hold still… 3·2·1", a shutter flash, then a small neutral "Checking photo…" pill.
struct SkyPhotoOverlay: View {
    let phase: SkyPhotoPhase
    let shutterCount: Int
    var analyzing = false
    /// The constellation being photographed, shown on the card ("Leo Minor · taking a sky photo").
    var subjectName: String?

    @State private var flash = 0.0

    var body: some View {
        ZStack {
            Color.white
                .opacity(flash)
                .ignoresSafeArea()

            switch phase {
            case .countdown(let n):
                holdStill(Text("\(n)").contentTransition(.numericText(countsDown: true)))
            case .shooting:
                holdStill(Image(systemName: "camera.aperture").symbolEffect(.pulse))
            case .idle:
                EmptyView()
            }

            VStack(spacing: 8) {
                if analyzing {
                    Label {
                        Text("Checking photo…")
                    } icon: {
                        SwiftUI.ProgressView().controlSize(.small)
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(.top, 72)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: phase)
        .animation(.easeOut(duration: 0.2), value: analyzing)
        .onChange(of: shutterCount) {
            flash = 0.8
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private func holdStill(_ symbol: some View) -> some View {
        VStack(spacing: 6) {
            symbol
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .frame(height: 52)
            Text("Hold still…")
                .font(.headline)
            Text(subjectName.map { "\($0) · taking a sky photo" } ?? "Taking a sky photo")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        // near-opaque so the ring and sky labels behind it can't show through
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.15)))
        .transition(.opacity)
    }
}

#Preview("Countdown") {
    SkyPhotoOverlay(phase: .countdown(2), shutterCount: 0, subjectName: "Leo Minor")
        .background(.black)
}

#Preview("Shooting") {
    SkyPhotoOverlay(phase: .shooting, shutterCount: 0)
        .background(.black)
}

#Preview("Analyzing") {
    SkyPhotoOverlay(phase: .idle, shutterCount: 1, analyzing: true)
        .background(.black)
}
