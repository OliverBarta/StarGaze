//
//  SupabaseFriendsDataSource.swift
//  StarGaze
//

import Foundation

/// Friends data from Supabase: the `feed` view and the `follows` table.
struct SupabaseFriendsDataSource: FriendsDataSource {
    let service: SupabaseService

    func fetchCaptures() async throws -> [FriendCapture] {
        try await service.fetchFeed().map { item in
            FriendCapture(
                id: item.id,
                friend: Friend(
                    id: item.userID,
                    name: item.displayName.map(\.strippingEmailDomain).flatMap { $0.isEmpty ? nil : $0 } ?? item.username,
                    avatarURL: item.avatarURL.flatMap(URL.init(string:))
                ),
                constellationName: item.constellationName,
                locationName: item.locationName,
                date: item.capturedAt
            )
        }
    }

    func follow(username: String) async throws {
        guard let me = service.profile else { throw FollowError.notSignedUp }
        guard username != me.username else { throw FollowError.cannotFollowSelf }
        guard let userID = try await service.userID(forUsername: username) else {
            throw FollowError.userNotFound
        }
        try await service.follow(userID: userID)
    }
}
