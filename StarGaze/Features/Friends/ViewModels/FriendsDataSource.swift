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

    /// Follows the user with this username, so their captures appear in `fetchCaptures()`.
    func follow(username: String) async throws
}

enum FollowError: Error {
    case notSignedUp
    case userNotFound
    case cannotFollowSelf
}
