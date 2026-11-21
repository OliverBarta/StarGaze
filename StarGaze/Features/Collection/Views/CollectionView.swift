//
//  CollectionView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct CollectionView: View {
    let constellations: [CaptureCardContent]

    /// The number of officially recognized constellations.
    private let totalConstellations = 88

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.medium), count: 2)

    init(constellations: [CaptureCardContent] = CaptureCardContent.collectionSamples) {
        self.constellations = constellations
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xLarge) {
                profileHeader

                VStack(alignment: .leading, spacing: Metrics.small) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Collection")
                            .font(.title3.bold())
                        Spacer()
                        Text("\(constellations.count) found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if constellations.isEmpty {
                        ContentUnavailableView {
                            Label("No constellations yet", systemImage: "sparkles")
                        } description: {
                            Text("Constellations you capture will show up here.")
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: Metrics.medium) {
                            ForEach(constellations.indices, id: \.self) { index in
                                ConstellationCard(constellation: constellations[index])
                            }
                        }
                    }
                }
            }
            .padding(Metrics.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var profileHeader: some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.xSmall) {
                Text("Joe")
                    .font(.title2.bold())
                Text("\(constellations.count) of \(totalConstellations) constellations")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(constellations.count), total: Double(totalConstellations))
                    .accessibilityHidden(true)
            }
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Collection") {
    CollectionView()
}

#Preview("Collection, dark") {
    CollectionView()
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    CollectionView(constellations: [])
}

extension CaptureCardContent {
    /// Placeholder captures until the collection has real data.
    static var collectionSamples: [CaptureCardContent] {
        let catalog = AssetConstellationCatalog()
        let finds: [(name: String, location: String, daysAgo: Int, firstFind: Bool)] = [
            ("Orion", "Fanshawe Conservation Area", 1, false),
            ("Camelopardalis", "Pinery Provincial Park", 3, true),
            ("Cassiopeia", "Komoka Provincial Park", 6, false),
            ("Draco", "Pinery Provincial Park", 12, true),
            ("Andromeda", "Fanshawe Conservation Area", 20, false),
            ("Ursa Major", "Komoka Provincial Park", 34, false),
        ]
        return finds.map { find in
            let rarity = Rarity.forConstellation(find.name)
            return CaptureCardContent(
                constellationName: find.name,
                locationName: find.location,
                date: Calendar.current.date(byAdding: .day, value: -find.daysAgo, to: .now) ?? .now,
                image: catalog.image(for: find.name),
                rarity: rarity,
                points: rarity.points,
                isFirstFind: find.firstFind
            )
        }
    }
}
