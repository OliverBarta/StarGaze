import SwiftUI

/// Top of the sky view: the dismissible instruction, and below it the "Checking photo…" pill.
/// Both sit in one stack inside the safe area, so they never overlap at any text size.
struct SkyTopBar: View {
    var showsInstruction = true
    /// Adds "· sky over London, ON" when there's no location fix.
    var usingFallbackLocation = false
    var checkingPhoto = false
    /// A short note in the same spot as "Checking photo…" (e.g. demo-mode captures).
    var notice: String?
    /// The compass heading is inaccurate: ask for a figure-8.
    var needsCalibration = false
    var onCloseInstruction: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            if showsInstruction {
                instruction
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if needsCalibration {
                calibrationPill
                    .transition(.opacity)
            }
            if checkingPhoto {
                checkingPill
                    .transition(.opacity)
            } else if let notice {
                noticePill(notice)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: showsInstruction)
        .animation(.easeOut(duration: 0.2), value: checkingPhoto)
        .animation(.easeOut(duration: 0.2), value: notice)
        .animation(.easeOut(duration: 0.2), value: needsCalibration)
    }

    private var instruction: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Point your phone at the sky")
                    .font(.subheadline.weight(.semibold))
                Text("Hold on a constellation, then capture it · tap constellation to learn more"
                     + (usingFallbackLocation ? " · sky over London, ON" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onCloseInstruction) {
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

    private var calibrationPill: some View {
        Label("Move your phone in a figure-8 to calibrate", systemImage: "infinity")
            .font(.footnote.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
    }

    private func noticePill(_ text: String) -> some View {
        Label(text, systemImage: "house")
            .font(.footnote.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
    }

    private var checkingPill: some View {
        Label {
            Text("Checking photo…")
        } icon: {
            SwiftUI.ProgressView().controlSize(.small)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .allowsHitTesting(false)
    }
}

#Preview("Instruction + checking photo") {
    ZStack(alignment: .top) {
        Color.black.ignoresSafeArea()
        SkyTopBar(showsInstruction: true, checkingPhoto: true)
            .padding()
    }
}

#Preview("Calibrate compass") {
    ZStack(alignment: .top) {
        Color.black.ignoresSafeArea()
        SkyTopBar(showsInstruction: true, needsCalibration: true)
            .padding()
    }
}

#Preview("Demo mode notice") {
    ZStack(alignment: .top) {
        Color.black.ignoresSafeArea()
        SkyTopBar(showsInstruction: true, notice: SkyScreen.demoNotice)
            .padding()
    }
}

#Preview("Large text") {
    ZStack(alignment: .top) {
        Color.black.ignoresSafeArea()
        SkyTopBar(showsInstruction: true, usingFallbackLocation: true, checkingPhoto: true)
            .padding()
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}
