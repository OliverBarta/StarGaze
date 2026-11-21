//
//  Friend.swift
//  StarGaze
//

import Foundation

struct Friend: Identifiable, Hashable {
    let id: UUID
    var name: String
    var avatarURL: URL?
}
