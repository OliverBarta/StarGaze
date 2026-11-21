//
//  FriendsDataSource.swift
//  StarGaze
//

import Foundation

/// Where the Friends page gets its data. Swap `MockFriendsDataSource` for a
/// backend-backed implementation without changing any views.
protocol FriendsDataSource {
    func fetchCaptures() async throws -> [FriendCapture]
}
