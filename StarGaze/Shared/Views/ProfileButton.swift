//
//  ProfileButton.swift
//  StarGaze
//

import SwiftUI

/// Toolbar button showing the signed-in user's picture. Opens their profile with a Sign Out button.
struct ProfileButton: View {
    @Environment(AuthService.self) private var auth
    @State private var isShowingProfile = false

    var body: some View {
        Button {
            isShowingProfile = true
        } label: {
            ProfilePictureView(url: auth.user?.pictureURL)
        }
        .accessibilityLabel("Profile")
        .sheet(isPresented: $isShowingProfile) {
            ProfileView()
                .presentationDetents([.medium])
        }
    }
}

#Preview("Signed in") {
    NavigationStack {
        Color(.systemGroupedBackground)
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileButton()
                }
            }
    }
    .environment(AuthService.preview(user: .preview))
}
