//
//  ConstellationCard.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

/// A compact capture for the two-column collection grid.
struct ConstellationCard: View {
    let constellation: CaptureCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CaptureImageView(image: constellation.image)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.imageCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    stampRow
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(constellation.constellationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(constellation.locationName)
                    .lineLimit(1)
                Text(constellation.date, format: .dateTime.month(.abbreviated).day().year())
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                RarityLabel(rarity: constellation.rarity)
                Spacer(minLength: Metrics.xSmall)
                Text("+\(constellation.points)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Metrics.small)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// Set stamps sit just over the image's top-right corner.
    @ViewBuilder
    private var stampRow: some View {
        if !constellation.stamps.isEmpty {
            HStack(spacing: -10) {
                ForEach(constellation.stamps) { set in
                    SetStampView(set: set, size: 40, slam: constellation.stampIsFresh)
                }
            }
            .offset(x: 6, y: -6)
        }
    }
}

#Preview {
    HStack(alignment: .top, spacing: Metrics.medium) {
        ConstellationCard(constellation: CaptureCardContent(
            constellationName: "Orion",
            locationName: "Fanshawe Conservation Area",
            date: .now,
            image: nil,
            rarity: .common,
            points: 10
        ))
        ConstellationCard(constellation: CaptureCardContent(
            constellationName: "Camelopardalis",
            locationName: "Pinery Provincial Park",
            date: .now.addingTimeInterval(-5 * 86400),
            image: nil,
            rarity: .legendary,
            points: 100
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
