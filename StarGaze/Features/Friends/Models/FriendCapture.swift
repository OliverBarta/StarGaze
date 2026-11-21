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
    var isFirstFind: Bool

    var rarity: Rarity {
        Rarity.forConstellation(constellationName)
    }

    /// Rarity points, doubled when this friend was the first in the group to find the constellation.
    var points: Int {
        isFirstFind ? rarity.points * 2 : rarity.points
    }
}
