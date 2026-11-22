//
//  CaptureCardView.swift
//  StarGaze
//

import SwiftUI

/// A single constellation capture. Features can add context above the photo through `header`.
struct CaptureCardView<Header: View>: View {
    let content: CaptureCardContent
    private let header: Header

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(content: CaptureCardContent, @ViewBuilder header: () -> Header) {
        self.content = content
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header

            Color.clear
                .aspectRatio(3 / 2, contentMode: .fit)
                .overlay {
                    CaptureImageView(image: content.image)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.imageCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: Metrics.xSmall) {
                Text(content.constellationName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("\(content.locationName) · \(dateText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            footer
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.xSmall))
            : AnyLayout(HStackLayout(spacing: Metrics.medium))

        return layout {
            RarityLabel(rarity: content.rarity)
            if content.isSpotted {
                Label("Spotted", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Rarity.legendary.color)
            }
            if !isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Text("+\(content.points)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Relative within the last week ("2 hours ago"), otherwise a short date ("Nov 20").
    private var dateText: Text {
        let calendar = Calendar.current
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now), content.date >= weekAgo {
            return Text(content.date, format: .relative(presentation: .named))
        }
        let isThisYear = calendar.isDate(content.date, equalTo: .now, toGranularity: .year)
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return Text(content.date, format: isThisYear ? format : format.year())
    }
}

extension CaptureCardView where Header == EmptyView {
    init(content: CaptureCardContent) {
        self.init(content: content) {
            EmptyView()
        }
    }
}

#if DEBUG
private extension CaptureCardContent {
    static let recentSample = CaptureCardContent(
        constellationName: "Andromeda",
        locationName: "Komoka Provincial Park",
        date: .now.addingTimeInterval(-2 * 3600),
        rarity: .uncommon,
        points: 25
    )

    static let olderSample = CaptureCardContent(
        constellationName: "Lynx",
        locationName: "Pinery Provincial Park",
        date: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now,
        rarity: .legendary,
        points: 100
    )

    static func sample(_ rarity: Rarity) -> CaptureCardContent {
        CaptureCardContent(
            constellationName: rarity.label + " Constellation",
            locationName: "Fanshawe Conservation Area",
            date: .now.addingTimeInterval(-5 * 3600),
            rarity: rarity,
            points: rarity.points
        )
    }
}

#Preview("No header, both date formats") {
    ScrollView {
        VStack(spacing: Metrics.large) {
            CaptureCardView(content: .recentSample)
            CaptureCardView(content: .olderSample)
        }
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("With header") {
    ScrollView {
        VStack(spacing: Metrics.large) {
            CaptureCardView(content: .recentSample) {
                Label("Header slot", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            CaptureCardView(content: .olderSample) {
                Label("Header slot", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Every rarity") {
    ScrollView {
        VStack(spacing: Metrics.large) {
            ForEach(Rarity.allCases, id: \.self) { rarity in
                CaptureCardView(content: .sample(rarity))
            }
        }
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: Metrics.large) {
            CaptureCardView(content: .recentSample)
            CaptureCardView(content: .olderSample)
        }
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}

#Preview("Accessibility size") {
    ScrollView {
        VStack(spacing: Metrics.large) {
            CaptureCardView(content: .recentSample)
            CaptureCardView(content: .olderSample)
        }
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Spotted") {
    CaptureCardView(content: CaptureCardContent(
        constellationName: "Orion",
        locationName: "London, Ontario",
        date: .now.addingTimeInterval(-600),
        rarity: .common,
        points: Rarity.common.points * 2,
        isSpotted: true
    ))
    .padding(Metrics.large)
    .background(Color(.systemGroupedBackground))
}
#endif
