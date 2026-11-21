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
    @Environment(AuthService.self) private var auth
    @Environment(SupabaseService.self) private var supabase
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
                    FriendsView(viewModel: FriendsViewModel(dataSource: SupabaseFriendsDataSource(service: supabase)))
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
        .task {
            await startSharing()
        }
        .onChange(of: selection) { old, _ in
            // stamps only slam in once
            if old == .collection { store.freshStamps = [] }
        }
    }

    /// Sets up the Supabase profile, uploads finds made offline or before sign-in,
    /// then shares each new find as it happens. Failures are retried on the next launch.
    private func startSharing() async {
        store.onDiscover = { [supabase] discovery in
            Task {
                do { try await supabase.uploadCaptures([discovery]) } catch { print("Couldn't share \(discovery.name): \(error)") }
            }
        }
        guard let user = auth.user else { return }
        do {
            try await supabase.syncProfile(for: user)
            try await supabase.uploadCaptures(Array(store.discoveries.values))
        } catch {
            print("Supabase sync failed: \(error)")
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
        .environment(SupabaseService.preview())
}
