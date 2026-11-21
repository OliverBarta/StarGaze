//
//  ContentView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Stars", systemImage: "star") {
                StarView()
            }
            Tab("Light Pollution", systemImage: "lightbulb") {
                LightPollutionView()
            }
            Tab("Friends", systemImage: "person.2") {
                FriendsView()
            }
            Tab("Collection", systemImage: "square.grid.2x2") {
                CollectionView()
            }
        }
    }
}

#Preview {
    ContentView()
}
