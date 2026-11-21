//
//  FriendStanding.swift
//  StarGaze
//

import Foundation

struct FriendStanding: Identifiable, Hashable {
    let friend: Friend
    let points: Int
    let rank: Int

    var id: Friend.ID {
        friend.id
    }

    /// Totals each friend's points for captures on or after `startDate`, highest first.
    /// Each constellation counts once per friend in that window, so rescanning it adds nothing.
    static func ranked(from captures: [FriendCapture], since startDate: Date) -> [FriendStanding] {
        var seen = Set<String>()
        let counted = captures.filter { capture in
            guard capture.date >= startDate else { return false }
            let key = "\(capture.friend.id)|\(ConstellationName.normalizedKey(for: capture.constellationName))"
            return seen.insert(key).inserted
        }
        let byFriend = Dictionary(grouping: counted, by: \.friend.id)

        let totals: [(friend: Friend, points: Int)] = byFriend.values.compactMap { friendCaptures in
            guard let friend = friendCaptures.first?.friend else { return nil }
            return (friend, friendCaptures.reduce(0) { $0 + $1.points })
        }

        let sorted = totals.sorted {
            $0.points != $1.points ? $0.points > $1.points : $0.friend.name < $1.friend.name
        }

        return sorted.enumerated().map { index, total in
            FriendStanding(friend: total.friend, points: total.points, rank: index + 1)
        }
    }
}
