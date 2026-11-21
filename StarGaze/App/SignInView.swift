//
//  SignInView.swift
//  StarGaze
//

import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: Metrics.xLarge) {
            Spacer()

            VStack(spacing: Metrics.small) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("StarGaze")
                    .font(.largeTitle.bold())
                Text("Find constellations. Beat your friends.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Metrics.medium) {
                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await auth.login() }
                } label: {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await auth.signUp() }
                } label: {
                    Text("Sign Up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(auth.isAuthenticating)
        }
        .padding(Metrics.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Signed out") {
    SignInView()
        .environment(AuthService.preview(user: nil))
}

#Preview("Login cancelled") {
    SignInView()
        .environment(AuthService.preview(user: nil, errorMessage: "Login was cancelled. Tap Log In to try again."))
}
