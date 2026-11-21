//
//  LeaderboardRow.swift
//  StarGaze
//

import SwiftUI

struct LeaderboardRow: View {
    let standing: FriendStanding

    @ScaledMetric(relativeTo: .body) private var rankWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Text(standing.rank, format: .number)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: rankWidth, alignment: .leading)

            if let avatarURL = standing.friend.avatarURL {
                AvatarView(url: avatarURL)
            }

            HStack(spacing: Metrics.xSmall) {
                Text(standing.friend.name)
                    .font(.body)
                    .lineLimit(2)
                if standing.rank == 1 {
                    Image(systemName: "crown.fill")
                        .font(.footnote)
                        .foregroundStyle(Rarity.legendary.color)
                        .accessibilityLabel("Leader")
                }
            }

            Spacer(minLength: Metrics.small)

            Text("\(standing.points) pts")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Friends without avatars") {
    let standings = FriendStanding.ranked(from: MockFriendsDataSource.sampleCaptures, since: .distantPast)
    VStack(spacing: 0) {
        ForEach(standings) { standing in
            LeaderboardRow(standing: standing)
        }
    }
    .background(Color(.secondarySystemGroupedBackground))
}
