import SwiftUI

/// A round, slightly tilted "passport stamp" for a completed constellation set.
/// When `slam` is true it thumps down onto the card the first time it appears.
struct SetStampView: View {
    let set: ConstellationSet
    var size: CGFloat = 44
    var slam = false

    @State private var landed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(set.color.opacity(0.18))
            Circle()
                .strokeBorder(set.color, lineWidth: 2)
            Circle()
                .strokeBorder(set.color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .padding(4)
            Image(systemName: set.symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(set.color)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-14))
        .shadow(color: set.color.opacity(0.6), radius: landed ? 4 : 0)
        .scaleEffect(slam && !landed ? 2.6 : 1)
        .opacity(slam && !landed ? 0 : 1)
        .onAppear {
            guard slam else { landed = true; return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.25)) {
                landed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        .accessibilityLabel("\(set.title) stamp")
    }
}

#Preview {
    HStack {
        ForEach(ConstellationSet.all) { set in
            SetStampView(set: set)
        }
    }
    .padding()
}
