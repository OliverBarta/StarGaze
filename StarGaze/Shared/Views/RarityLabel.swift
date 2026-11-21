//
//  RarityLabel.swift
//  StarGaze
//

import SwiftUI

struct RarityLabel: View {
    let rarity: Rarity

    var body: some View {
        Label(rarity.label, systemImage: rarity.symbol)
            .font(.caption)
            .imageScale(.small)
            .foregroundStyle(rarity.color)
    }
}

#Preview("Every rarity") {
    VStack(alignment: .leading, spacing: Metrics.small) {
        ForEach(Rarity.allCases, id: \.self) { rarity in
            RarityLabel(rarity: rarity)
        }
    }
    .padding()
}

#Preview("Every rarity, dark") {
    VStack(alignment: .leading, spacing: Metrics.small) {
        ForEach(Rarity.allCases, id: \.self) { rarity in
            RarityLabel(rarity: rarity)
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
