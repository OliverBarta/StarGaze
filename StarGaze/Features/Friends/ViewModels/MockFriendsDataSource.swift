//
//  MockFriendsDataSource.swift
//  StarGaze
//

import Foundation

struct MockFriendsDataSource: FriendsDataSource {
    var captures: [FriendCapture] = MockFriendsDataSource.sampleCaptures
    var delay: Duration = .seconds(1)
    var shouldFail = false

    func fetchCaptures() async throws -> [FriendCapture] {
        try await Task.sleep(for: delay)
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        return captures
    }
}

extension MockFriendsDataSource {
    static let maya = Friend(id: UUID(), name: "Maya Chen")
    static let jordan = Friend(id: UUID(), name: "Jordan Okafor")
    static let priya = Friend(id: UUID(), name: "Priya Sharma")
    static let liam = Friend(id: UUID(), name: "Liam Tremblay")

    /// Dates are relative to now, so the 7-day leaderboard always has data.
    static var sampleCaptures: [FriendCapture] {
        [
            capture(maya, "Cassiopeia", at: "Fanshawe Conservation Area", hoursAgo: 2),
            capture(jordan, "Camelopardalis", at: "Pinery Provincial Park", hoursAgo: 5, firstFind: true),
            capture(priya, "Andromeda", at: "Komoka Provincial Park", hoursAgo: 9, firstFind: true),
            capture(liam, "Orion", at: "Port Stanley Main Beach", hoursAgo: 26),
            capture(maya, "Perseus", at: "Westminster Ponds", hoursAgo: 30, firstFind: true),
            capture(jordan, "Pegasus", at: "Springbank Park", hoursAgo: 50),
            capture(priya, "Cepheus", at: "Fanshawe Conservation Area", hoursAgo: 73),
            capture(liam, "Lynx", at: "Pinery Provincial Park", hoursAgo: 98),
        ]
    }

    private static func capture(
        _ friend: Friend,
        _ constellation: String,
        at location: String,
        hoursAgo: Double,
        firstFind: Bool = false
    ) -> FriendCapture {
        FriendCapture(
            id: UUID(),
            friend: friend,
            constellationName: constellation,
            locationName: location,
            date: Date().addingTimeInterval(-hoursAgo * 3600),
            isFirstFind: firstFind
        )
    }
}
