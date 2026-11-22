//
//  FriendsDataSource.swift
//  StarGaze
//

import Foundation

/// Where the Friends page gets its data: `SupabaseFriendsDataSource` in the app,
/// `MockFriendsDataSource` (DEBUG only) in previews.
protocol FriendsDataSource {
    /// Every capture by the user's friends, including repeat scans of the same constellation.
    /// The feed shows all of them; the leaderboard counts each constellation once per friend
    /// per week (see `FriendStanding.ranked`), so implementations shouldn't dedupe.
    func fetchCaptures() async throws -> [FriendCapture]

    /// Follows the user with this username, so their captures appear in `fetchCaptures()`.
    func follow(username: String) async throws

    /// The signed-in user, for their own leaderboard row (nil until their profile is known).
    var currentUser: Friend? { get }

    /// The signed-in user's own captures, for the leaderboard only (never the feed).
    func fetchMyCaptures() async throws -> [FriendCapture]

    /// Everyone the user follows, so friends without captures still get a 0-point leaderboard row.
    func fetchFriends() async throws -> [Friend]
}

enum FollowError: Error {
    case notSignedUp
    case userNotFound
    case cannotFollowSelf
}
