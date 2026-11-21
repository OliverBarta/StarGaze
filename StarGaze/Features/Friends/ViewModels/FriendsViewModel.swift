//
//  FriendsViewModel.swift
//  StarGaze
//

import Foundation
import Observation

@Observable
final class FriendsViewModel {
    /// Sorted newest first.
    private(set) var captures: [FriendCapture] = []
    /// True only during the initial load; pull to refresh uses the system indicator instead.
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    private let dataSource: any FriendsDataSource
    private let catalog: any ConstellationCatalog

    init(dataSource: any FriendsDataSource, catalog: any ConstellationCatalog = AssetConstellationCatalog()) {
        self.dataSource = dataSource
        self.catalog = catalog
    }

    /// Leaderboard for the last 7 days, highest points first.
    var standings: [FriendStanding] {
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return FriendStanding.ranked(from: captures, since: startDate)
    }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        await fetch()
        isLoading = false
    }

    func refresh() async {
        await fetch()
    }

    func cardContent(for capture: FriendCapture) -> CaptureCardContent {
        capture.cardContent(using: catalog)
    }

    func addFriend(username: String) async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // TODO: Send the friend request to the backend here (e.g. add a method to FriendsDataSource),
        // surface failures through errorMessage, and call refresh() on success.
    }

    private func fetch() async {
        do {
            let fetched = try await dataSource.fetchCaptures()
            captures = fetched.sorted { $0.date > $1.date }
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            // The view went away or the refresh was cancelled; keep what we have.
        } catch {
            errorMessage = "Couldn't load your friends' finds. Check your connection and try again."
        }
    }
}
