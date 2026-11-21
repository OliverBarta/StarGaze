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

#Preview("Repeat scans count once") {
    // Maya scans Orion three times (10 pts once), Jordan finds Lyra once (25 pts),
    // so Jordan leads. Without the dedupe Maya would lead with 30.
    let maya = MockFriendsDataSource.maya
    let jordan = MockFriendsDataSource.jordan
    let captures = [
        FriendCapture(id: UUID(), friend: maya, constellationName: "Orion", locationName: "Springbank Park", date: .now),
        FriendCapture(id: UUID(), friend: maya, constellationName: "orion ", locationName: "Springbank Park", date: .now.addingTimeInterval(-3600)),
        FriendCapture(id: UUID(), friend: maya, constellationName: "Orion", locationName: "Westminster Ponds", date: .now.addingTimeInterval(-86_400)),
        FriendCapture(id: UUID(), friend: jordan, constellationName: "Lyra", locationName: "Komoka Provincial Park", date: .now),
    ]
    ScrollView {
        LeaderboardSection(standings: FriendStanding.ranked(from: captures, since: .distantPast))
            .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
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
