//
//  FriendsErrorView.swift
//  StarGaze
//

import SwiftUI

struct FriendsErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load finds", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    FriendsErrorView(message: "Couldn't load your friends' finds. Check your connection and try again.") {}
}
