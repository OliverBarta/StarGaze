//
//  Friend.swift
//  StarGaze
//

import Foundation

struct Friend: Identifiable, Hashable {
    /// The friend's Auth0 user ID.
    let id: String
    var name: String
    var avatarURL: URL?
}
