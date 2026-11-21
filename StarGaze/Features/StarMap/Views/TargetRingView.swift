import SwiftUI

/// Centre-of-screen indicator for the targeted constellation, so it's always clear which one you're collecting.
struct TargetRingView: View {
    let target: SkyTarget

    private static let gold = Color(red: 1, green: 0.8, blue: 0.4)

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(target.isCollected ? 0.12 : 0.2), lineWidth: 3)
                if target.isCollected {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Self.gold.opacity(0.85))
                } else {
                    Circle()
                        .trim(from: 0, to: target.progress)
                        .stroke(Self.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: target.progress)
                }
            }
            .frame(width: 58, height: 58)
            Text(target.name.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .kerning(3)
                .foregroundStyle(.white.opacity(target.isCollected ? 0.6 : 0.85))
            if target.isCollected {
                Text("Collected")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Collecting") {
    TargetRingView(target: SkyTarget(name: "Orion", progress: 0.6, isCollected: false))
        .padding()
        .background(.black)
}

#Preview("Collected") {
    TargetRingView(target: SkyTarget(name: "Lyra", progress: 0, isCollected: true))
        .padding()
        .background(.black)
}
