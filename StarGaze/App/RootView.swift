//
//  RootView.swift
//  StarGaze
//

import SwiftUI

/// Chooses between restoring the session, the sign-in screen and the app's tabs.
struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            } else if auth.user == nil {
                SignInView()
            } else {
                ContentView()
            }
        }
        .animation(.default, value: auth.user?.id)
        .task {
            await auth.restoreSession()
        }
    }
}

#Preview("Restoring session") {
    RootView()
        .environment(AuthService.preview(user: nil, isLoading: true))
}

#Preview("Signed out") {
    RootView()
        .environment(AuthService.preview(user: nil))
}

#Preview("Signed in") {
    RootView()
        .environment(AuthService.preview(user: .preview))
}
