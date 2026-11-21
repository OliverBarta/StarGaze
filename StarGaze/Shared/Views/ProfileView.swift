//
//  ProfileView.swift
//  StarGaze
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Metrics.medium) {
                if let user = auth.user {
                    ProfilePictureView(url: user.pictureURL, size: 72)
                    Text(user.displayName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if let email = user.email, email != user.displayName {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: Metrics.xLarge)

                Button(role: .destructive) {
                    Task { await auth.logout() }
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(Metrics.xLarge)
            .frame(maxWidth: .infinity)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Signed in") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            ProfileView()
                .presentationDetents([.medium])
        }
        .environment(AuthService.preview(user: .preview))
}
