//
//  FriendCapture.swift
//  StarGaze
//

import Foundation

struct FriendCapture: Identifiable, Hashable {
    let id: UUID
    var friend: Friend
    var constellationName: String
    var locationName: String
    var date: Date
    /// Confirmed by a good sky photo. Only known for the user's own finds (stored on the device);
    /// friends' captures don't carry a level yet.
    var isSpotted = false

    var rarity: Rarity {
        Rarity.forConstellation(constellationName)
    }

    /// The constellation's rarity points, doubled when Spotted.
    var points: Int {
        rarity.points * (isSpotted ? 2 : 1)
    }
}
