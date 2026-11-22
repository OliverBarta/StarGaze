//
//  ProfileView.swift
//  StarGaze
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SupabaseService.self) private var supabase: SupabaseService?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DemoMode.defaultsKey) private var demoMode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Metrics.medium) {
                if let user = auth.user {
                    ProfilePictureView(url: user.pictureURL, size: 72)
                    Text(user.displayName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if let username = supabase?.profile?.username {
                        Text("@\(username)")
                            .font(.headline)
                            .foregroundStyle(.tint)
                            .textSelection(.enabled)
                    }
                    if let email = user.email, email != user.displayName {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: Metrics.xLarge)

                Toggle("Demo mode: allow indoor captures", isOn: $demoMode)
                    .font(.subheadline)

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

#if DEBUG
#Preview("Signed in") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            ProfileView()
                .presentationDetents([.medium])
        }
        .environment(AuthService.preview(user: .preview))
        .environment(SupabaseService.preview())
}
#endif
