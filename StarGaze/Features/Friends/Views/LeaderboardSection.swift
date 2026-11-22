//
//  LeaderboardSection.swift
//  StarGaze
//

import SwiftUI

struct LeaderboardSection: View {
    let standings: [FriendStanding]

    private static let visibleCount = 5

    private var topStandings: [FriendStanding] {
        Array(standings.prefix(Self.visibleCount))
    }

    /// The user's own row when they're outside the top 5, shown below it with their real rank.
    private var myStandingBelow: FriendStanding? {
        guard let mine = standings.first(where: \.isMe), mine.rank > Self.visibleCount else { return nil }
        return mine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("This week")
                .font(.title3.bold())

            VStack(spacing: 0) {
                ForEach(topStandings) { standing in
                    LeaderboardRow(standing: standing)
                    if standing.id != topStandings.last?.id {
                        Divider()
                            .padding(.leading, Metrics.large)
                    }
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))

            if let myStandingBelow {
                LeaderboardRow(standing: myStandingBelow)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
                    .padding(.top, Metrics.xSmall)
            }
        }
    }
}

private enum LeaderboardPreviewData {
    static let me = MockFriendsDataSource.alex

    static let friends: [Friend] = [
        MockFriendsDataSource.maya, MockFriendsDataSource.jordan, MockFriendsDataSource.priya,
        MockFriendsDataSource.liam, Friend(id: "mock|sam", name: "Sam Nguyen"),
        Friend(id: "mock|noor", name: "Noor Haddad"), Friend(id: "mock|eli", name: "Eli Martin"),
    ]

    /// Each friend finds `count` different constellations this week.
    static func captures(_ friend: Friend, _ names: [String]) -> [FriendCapture] {
        names.map { MockFriendsDataSource.capture(friend, $0, at: "Springbank Park", hoursAgo: 10) }
    }

    static var friendCaptures: [FriendCapture] {
        captures(friends[0], ["Lyra", "Cygnus", "Orion"])
            + captures(friends[1], ["Lynx", "Draco"])
            + captures(friends[2], ["Perseus", "Andromeda"])
            + captures(friends[3], ["Orion", "Cassiopeia"])
            + captures(friends[4], ["Pegasus"])
            + captures(friends[5], ["Cepheus"])
            + captures(friends[6], ["Ursa Major"])
    }
}

#Preview("Me in the top 5") {
    var spotted = MockFriendsDataSource.capture(LeaderboardPreviewData.me, "Camelopardalis", at: "Home", hoursAgo: 3)
    spotted.isSpotted = true
    let captures = LeaderboardPreviewData.friendCaptures + [spotted]
    return ScrollView {
        LeaderboardSection(standings: FriendStanding.ranked(from: captures, since: .distantPast,
                                                            me: LeaderboardPreviewData.me))
            .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Me below 5th") {
    ScrollView {
        LeaderboardSection(standings: FriendStanding.ranked(from: LeaderboardPreviewData.friendCaptures,
                                                            since: .distantPast, me: LeaderboardPreviewData.me))
            .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
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
