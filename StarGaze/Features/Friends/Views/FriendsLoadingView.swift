//
//  FriendsLoadingView.swift
//  StarGaze
//

import SwiftUI

/// Skeleton version of the feed, so the layout doesn't jump when data arrives.
struct FriendsLoadingView: View {
    private static let placeholderFriend = Friend(id: UUID(), name: "Loading Friend")

    private static let placeholderStandings = (1...4).map { rank in
        FriendStanding(friend: Friend(id: UUID(), name: "Friend Name"), points: 100, rank: rank)
    }

    private static let placeholderCaptures = (0..<2).map { _ in
        CaptureCardContent(
            constellationName: "Constellation",
            locationName: "Somewhere dark",
            date: .now,
            rarity: .common,
            points: 10,
            isFirstFind: false
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xLarge) {
                LeaderboardSection(standings: Self.placeholderStandings)
                VStack(spacing: Metrics.large) {
                    ForEach(Self.placeholderCaptures.indices, id: \.self) { index in
                        CaptureCardView(content: Self.placeholderCaptures[index]) {
                            FriendCaptureHeader(friend: Self.placeholderFriend)
                        }
                    }
                }
            }
            .padding(Metrics.large)
        }
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
        .phaseAnimator([1.0, 0.5]) { content, opacity in
            content.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading friends' finds")
    }
}

#Preview {
    FriendsLoadingView()
        .background(Color(.systemGroupedBackground))
}
