//
//  AppUser.swift
//  StarGaze
//

import Auth0
import Foundation

/// The signed-in user, built from the Auth0 ID token's profile claims.
struct AppUser: Identifiable, Hashable {
    let id: String
    var name: String?
    var nickname: String?
    var email: String?
    var pictureURL: URL?

    var displayName: String {
        name ?? nickname ?? email ?? "Stargazer"
    }
}

extension AppUser {
    init(profile: UserProfile) {
        self.init(
            id: profile.sub,
            name: profile.name,
            nickname: profile.nickname,
            email: profile.email,
            pictureURL: profile.picture
        )
    }
}

#if DEBUG
extension AppUser {
    static let preview = AppUser(
        id: "auth0|preview",
        name: "Alex Rivera",
        nickname: "alex",
        email: "alex@example.com"
    )
}
#endif
