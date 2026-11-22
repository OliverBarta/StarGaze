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
    @State private var readings = SkyReadingStore()
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
                    FriendsView(viewModel: FriendsViewModel(dataSource: SupabaseFriendsDataSource(service: supabase),
                                                           localFinds: { [store] in Array(store.discoveries.values) }))
                }
                Tab("Collection", systemImage: "square.grid.2x2", value: AppTab.collection) {
                    CollectionView(constellations: store.cards)
                }
            }

            // Set-complete cutscene plays over everything, then jumps to the collection.
            if let completion = store.cutsceneToPlay {
                cutscene(for: completion)
                    .id(completion.id)
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .environment(store)
        .environment(readings)
        .task {
            await startSharing()
        }
        .onChange(of: selection) { old, new in
            // stamps only slam in once
            if old == .collection { store.freshStamps = [] }
            if new == .collection { Task { await refreshCollection() } }
        }
    }

    /// Sets up the Supabase profile and loads the user's finds from it, uploads light readings made
    /// offline or before sign-in, then shares each new one as it happens. Reading uploads that fail
    /// are retried on the next launch; finds are only collected once Supabase has saved them.
    private func startSharing() async {
        readings.onAdd = { _ in
            Task { await uploadReadings() }
        }
        await uploadReadings()
        store.saveCapture = { [supabase, auth] discovery in
            if supabase.profile == nil {
                guard let user = auth.user else { throw SupabaseError.notSignedUp }
                try await supabase.syncProfile(for: user)
            }
            try await supabase.saveCapture(discovery)
        }
        store.fetchCaptures = { [supabase] in
            guard let me = supabase.profile else { throw SupabaseError.notSignedUp }
            return try await supabase.fetchCaptures(userID: me.id).map {
                DiscoveryStore.Discovery(name: $0.constellationName, date: $0.capturedAt,
                                         place: $0.locationName, level: $0.level)
            }
        }
        guard let user = auth.user else { return }
        do {
            try await supabase.syncProfile(for: user)
        } catch {
            print("Supabase profile sync failed: \(error)")
            return
        }
        await refreshCollection()
    }

    /// Loads the user's finds from Supabase (on launch and whenever Collection opens).
    private func refreshCollection() async {
        do {
            if supabase.profile == nil, let user = auth.user { try await supabase.syncProfile(for: user) }
            try await store.refresh()
        } catch {
            print("Couldn't load the collection: \(error)")
        }
    }

    /// Inserts reliable sky readings into `light_readings` so they show on the map.
    private func uploadReadings() async {
        await readings.uploadPending { [supabase] reading in
            try await supabase.insertLightReading(latitude: reading.latitude, longitude: reading.longitude,
                                                  strength: reading.strength)
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

#if DEBUG
#Preview {
    ContentView()
        .environment(AuthService.preview(user: .preview))
        .environment(SupabaseService.preview())
}
#endif
