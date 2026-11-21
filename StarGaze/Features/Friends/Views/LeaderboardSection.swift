//
//  LeaderboardSection.swift
//  StarGaze
//

import SwiftUI

struct LeaderboardSection: View {
    let standings: [FriendStanding]

    private var visibleStandings: [FriendStanding] {
        Array(standings.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("This week")
                .font(.title3.bold())

            VStack(spacing: 0) {
                ForEach(visibleStandings) { standing in
                    LeaderboardRow(standing: standing)
                    if standing.id != visibleStandings.last?.id {
                        Divider()
                            .padding(.leading, Metrics.large)
                    }
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
            )
        }
    }
}

#Preview {
    ScrollView {
        LeaderboardSection(
            standings: FriendStanding.ranked(from: MockFriendsDataSource.sampleCaptures, since: .distantPast)
        )
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
}
