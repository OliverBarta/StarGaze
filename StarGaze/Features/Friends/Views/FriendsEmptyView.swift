//
//  FriendsEmptyView.swift
//  StarGaze
//

import SwiftUI

struct FriendsEmptyView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No finds yet", systemImage: "binoculars")
        } description: {
            Text("When your friends capture constellations, they'll show up here. Head out tonight and be first on the board!")
        }
    }
}

#Preview {
    FriendsEmptyView()
}
