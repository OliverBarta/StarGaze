//
//  FriendsDataSource.swift
//  StarGaze
//

import Foundation

/// Where the Friends page gets its data. Swap `MockFriendsDataSource` for a
/// backend-backed implementation without changing any views.
protocol FriendsDataSource {
    /// Every capture by the user's friends, including repeat scans of the same constellation.
    /// The feed shows all of them; the leaderboard counts each constellation once per friend
    /// per week (see `FriendStanding.ranked`), so implementations shouldn't dedupe.
    func fetchCaptures() async throws -> [FriendCapture]
}
