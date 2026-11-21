//
//  FriendsLoadingView.swift
//  StarGaze
//

import SwiftUI

/// Shown until friends' finds have loaded. A plain spinner, so nothing animates into place.
struct FriendsLoadingView: View {
    var body: some View {
        SwiftUI.ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading friends' finds")
    }
}

#Preview {
    FriendsLoadingView()
        .background(Color(.systemGroupedBackground))
}
