//
//  ConstellationCard.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftData
import SwiftUI

struct ConstellationCard: View {
    let constellation: ConstellationImageName

    var body: some View {
        VStack(spacing: 8) {
            Color.black
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(constellation.image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(constellation.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .aspectRatio(1, contentMode: .fit)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ConstellationCard(constellation: ConstellationImageName(name: "Orion", image: "orion"))
        .frame(width: 180)
}
