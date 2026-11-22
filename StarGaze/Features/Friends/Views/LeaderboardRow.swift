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
                    .font(standing.isMe ? .body.weight(.semibold) : .body)
                    .lineLimit(2)
                if standing.isMe {
                    Text("You")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
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
        .background(standing.isMe ? Color.accentColor.opacity(0.08) : .clear)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Friends without avatars") {
    let standings = FriendStanding.ranked(from: MockFriendsDataSource.sampleCaptures, since: .distantPast)
    VStack(spacing: 0) {
        ForEach(standings) { standing in
            LeaderboardRow(standing: standing)
        }
    }
    .background(Color(.secondarySystemGroupedBackground))
}
#endif
