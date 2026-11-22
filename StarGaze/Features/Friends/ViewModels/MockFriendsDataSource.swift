//
//  MockFriendsDataSource.swift
//  StarGaze
//

import Foundation

#if DEBUG
/// Sample friends and captures for previews (DEBUG builds only; the app uses `SupabaseFriendsDataSource`).
struct MockFriendsDataSource: FriendsDataSource {
    var captures: [FriendCapture] = MockFriendsDataSource.sampleCaptures
    var delay: Duration = .seconds(1)
    var shouldFail = false
    var me: Friend? = MockFriendsDataSource.alex
    var myCaptures: [FriendCapture] = MockFriendsDataSource.sampleMyCaptures
    var friends: [Friend] = [MockFriendsDataSource.maya, MockFriendsDataSource.jordan,
                             MockFriendsDataSource.priya, MockFriendsDataSource.liam]

    func fetchCaptures() async throws -> [FriendCapture] {
        try await Task.sleep(for: delay)
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        return captures
    }

    func follow(username: String) async throws {
        try await Task.sleep(for: delay)
        if shouldFail {
            throw FollowError.userNotFound
        }
    }

    var currentUser: Friend? { me }

    func fetchMyCaptures() async throws -> [FriendCapture] {
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        return myCaptures
    }

    func fetchFriends() async throws -> [Friend] {
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        return friends
    }
}

extension MockFriendsDataSource {
    static let maya = Friend(id: "mock|maya", name: "Maya Chen")
    static let jordan = Friend(id: "mock|jordan", name: "Jordan Okafor")
    static let priya = Friend(id: "mock|priya", name: "Priya Sharma")
    static let liam = Friend(id: "mock|liam", name: "Liam Tremblay")
    static let alex = Friend(id: "mock|alex", name: "Alex Rivera")

    /// The signed-in user's own finds: one Spotted (double points).
    static var sampleMyCaptures: [FriendCapture] {
        var lyra = capture(alex, "Lyra", at: "Springbank Park", hoursAgo: 12)
        lyra.isSpotted = true
        return [lyra, capture(alex, "Orion", at: "Springbank Park", hoursAgo: 40)]
    }

    /// Dates are relative to now, so the 7-day leaderboard always has data.
    static var sampleCaptures: [FriendCapture] {
        [
            capture(maya, "Cassiopeia", at: "Fanshawe Conservation Area", hoursAgo: 2),
            capture(jordan, "Camelopardalis", at: "Pinery Provincial Park", hoursAgo: 5),
            capture(priya, "Andromeda", at: "Komoka Provincial Park", hoursAgo: 9),
            // A repeat scan: shows in the feed but adds no leaderboard points this week.
            capture(maya, "Cassiopeia", at: "Westminster Ponds", hoursAgo: 20),
            capture(liam, "Orion", at: "Port Stanley Main Beach", hoursAgo: 26),
            capture(maya, "Perseus", at: "Westminster Ponds", hoursAgo: 30),
            capture(jordan, "Pegasus", at: "Springbank Park", hoursAgo: 50),
            capture(priya, "Cepheus", at: "Fanshawe Conservation Area", hoursAgo: 73),
            capture(liam, "Lynx", at: "Pinery Provincial Park", hoursAgo: 98),
        ]
    }

    static func capture(
        _ friend: Friend,
        _ constellation: String,
        at location: String,
        hoursAgo: Double
    ) -> FriendCapture {
        FriendCapture(
            id: UUID(),
            friend: friend,
            constellationName: constellation,
            locationName: location,
            date: Date().addingTimeInterval(-hoursAgo * 3600)
        )
    }
}
#endif
