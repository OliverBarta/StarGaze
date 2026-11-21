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

    var rarity: Rarity {
        Rarity.forConstellation(constellationName)
    }

    /// The constellation's rarity points.
    var points: Int {
        rarity.points
    }
}
