//
//  StarGazeApp.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

@main
struct StarGazeApp: App {
    @State private var auth: AuthService
    @State private var supabase: SupabaseService

    init() {
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _supabase = State(initialValue: SupabaseService(accessToken: { try await auth.accessToken() }))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(supabase)
        }
    }
}
