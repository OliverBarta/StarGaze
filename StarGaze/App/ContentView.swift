//
//  ContentView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

enum AppTab: Hashable {
    case stars, lightPollution, friends, collection
}

struct ContentView: View {
    @State private var store = DiscoveryStore()
    @State private var selection: AppTab = .stars

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                Tab("Stars", systemImage: "star", value: AppTab.stars) {
                    StarView()
                }
                Tab("Light Pollution", systemImage: "lightbulb", value: AppTab.lightPollution) {
                    StargazingSpotsView()
                }
                Tab("Friends", systemImage: "person.2", value: AppTab.friends) {
                    FriendsView()
                }
                Tab("Collection", systemImage: "square.grid.2x2", value: AppTab.collection) {
                    CollectionView(constellations: store.cards)
                }
            }

            // Set-complete cutscene plays over everything, then jumps to the collection.
            if let completion = store.pendingCompletions.first {
                cutscene(for: completion)
                    .id(completion.id)
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .environment(store)
        .onChange(of: selection) { old, _ in
            // stamps only slam in once
            if old == .collection { store.freshStamps = [] }
        }
    }

    /// Auriga gets its own crystal-flare cutscene; everything else gets the set cutscene.
    @ViewBuilder
    private func cutscene(for completion: DiscoveryStore.Completion) -> some View {
        let done = {
            withAnimation(.easeInOut(duration: 0.5)) {
                store.finishCutscene(completion)
                if store.pendingCompletions.isEmpty && !completion.isTest {
                    selection = .collection
                }
            }
        }
        if completion.names.first == "Auriga" {
            AurigaCutsceneView(completion: completion, onFinish: done)
        } else {
            SetCutsceneView(completion: completion, onFinish: done)
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService.preview(user: .preview))
}
