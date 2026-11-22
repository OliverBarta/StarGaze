//
//  CollectionView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct CollectionView: View {
    @Environment(AuthService.self) private var auth

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
            ProfilePictureView(url: auth.user?.pictureURL, size: 48)

            VStack(alignment: .leading, spacing: Metrics.xSmall) {
                Text(auth.user?.displayName ?? "Stargazer")
                    .font(.title2.bold())
                Text("\(constellations.count) of \(totalConstellations) constellations")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SwiftUI.ProgressView(value: Double(constellations.count), total: Double(totalConstellations))
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

#if DEBUG
#Preview("Collection") {
    CollectionView()
        .environment(AuthService.preview(user: .preview))
}

#Preview("Collection, dark") {
    CollectionView()
        .environment(AuthService.preview(user: .preview))
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    CollectionView(constellations: [])
        .environment(AuthService.preview(user: .preview))
}
#endif

extension CaptureCardContent {
    /// Placeholder captures until the collection has real data.
    static var collectionSamples: [CaptureCardContent] {
        let catalog = JSONConstellationCatalog()
        let finds: [(name: String, location: String, daysAgo: Int)] = [
            ("Orion", "Fanshawe Conservation Area", 1),
            ("Camelopardalis", "Pinery Provincial Park", 3),
            ("Cassiopeia", "Komoka Provincial Park", 6),
            ("Draco", "Pinery Provincial Park", 12),
            ("Andromeda", "Fanshawe Conservation Area", 20),
            ("Ursa Major", "Komoka Provincial Park", 34),
        ]
        return finds.map { find in
            let rarity = Rarity.forConstellation(find.name)
            return CaptureCardContent(
                constellationName: find.name,
                locationName: find.location,
                date: Calendar.current.date(byAdding: .day, value: -find.daysAgo, to: .now) ?? .now,
                image: catalog.image(for: find.name),
                rarity: rarity,
                points: rarity.points
            )
        }
    }
}
