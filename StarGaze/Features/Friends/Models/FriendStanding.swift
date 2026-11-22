//
//  FriendStanding.swift
//  StarGaze
//

import Foundation

struct FriendStanding: Identifiable, Hashable {
    let friend: Friend
    let points: Int
    let rank: Int
    /// The signed-in user's own row.
    var isMe = false

    var id: Friend.ID {
        friend.id
    }

    /// Totals each friend's points for captures on or after `startDate`, highest first.
    /// Each constellation counts once per friend in that window, so rescanning it adds nothing.
    /// With `me`, the user always gets a row (0 points if they have no captures this week);
    /// pass their captures in `captures` with `friend == me`. Everyone in `everyone` (the people
    /// the user follows) gets a row too, at 0 points if they have no captures this week.
    static func ranked(from captures: [FriendCapture], since startDate: Date, me: Friend? = nil,
                       everyone: [Friend] = []) -> [FriendStanding] {
        var seen = Set<String>()
        let counted = captures.filter { capture in
            guard capture.date >= startDate else { return false }
            let key = "\(capture.friend.id)|\(ConstellationName.normalizedKey(for: capture.constellationName))"
            return seen.insert(key).inserted
        }
        let byFriend = Dictionary(grouping: counted, by: \.friend.id)

        var totals: [(friend: Friend, points: Int)] = byFriend.values.compactMap { friendCaptures in
            guard let friend = friendCaptures.first?.friend else { return nil }
            return (friend, friendCaptures.reduce(0) { $0 + $1.points })
        }
        var listed = Set(byFriend.keys)
        for person in everyone + (me.map { [$0] } ?? []) where !listed.contains(person.id) {
            listed.insert(person.id)
            totals.append((person, 0))
        }

        let sorted = totals.sorted {
            $0.points != $1.points ? $0.points > $1.points : $0.friend.name < $1.friend.name
        }

        return sorted.enumerated().map { index, total in
            FriendStanding(friend: total.friend, points: total.points, rank: index + 1,
                           isMe: total.friend.id == me?.id)
        }
    }
}
