//
//  FriendsViewModel.swift
//  StarGaze
//

import Foundation
import Observation

@Observable
final class FriendsViewModel {
    /// Friends' captures, sorted newest first. The feed shows only these.
    private(set) var captures: [FriendCapture] = []
    /// The user's own captures, for the leaderboard only.
    private(set) var myCaptures: [FriendCapture] = []
    /// The user's leaderboard identity.
    private(set) var me = FriendsViewModel.fallbackMe
    /// True only during the initial load; pull to refresh uses the system indicator instead.
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false
    /// Set when adding a friend fails; the view shows it as an alert.
    var addFriendError: String?

    private let dataSource: any FriendsDataSource
    private let catalog: any ConstellationCatalog
    /// The user's finds on this device: the fallback when Supabase can't return their captures,
    /// and the only place Spotted is known.
    private let localFinds: () -> [DiscoveryStore.Discovery]

    /// Used when the user's profile isn't known yet.
    static let fallbackMe = Friend(id: "local|me", name: "You")

    init(dataSource: any FriendsDataSource, catalog: any ConstellationCatalog = JSONConstellationCatalog(),
         localFinds: @escaping () -> [DiscoveryStore.Discovery] = { [] }) {
        self.dataSource = dataSource
        self.catalog = catalog
        self.localFinds = localFinds
    }

    /// Leaderboard for the last 7 days, highest points first, including the user.
    var standings: [FriendStanding] {
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return FriendStanding.ranked(from: captures + myCaptures, since: startDate, me: me)
    }

    /// The user's captures: from Supabase when available, otherwise the local finds. Spotted comes
    /// from the local finds either way (the server doesn't store levels).
    static func myCaptures(remote: [FriendCapture]?, local: [DiscoveryStore.Discovery], me: Friend) -> [FriendCapture] {
        let spotted = Set(local.filter { $0.level == .spotted }.map { ConstellationName.normalizedKey(for: $0.name) })
        let base = remote ?? local.map {
            FriendCapture(id: UUID(), friend: me, constellationName: $0.name, locationName: $0.place, date: $0.date)
        }
        return base.map { capture in
            var mine = capture
            mine.friend = me
            mine.isSpotted = spotted.contains(ConstellationName.normalizedKey(for: capture.constellationName))
            return mine
        }
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
        var name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") { name.removeFirst() }
        guard !name.isEmpty else { return }
        do {
            try await dataSource.follow(username: name)
            await refresh()
        } catch FollowError.userNotFound {
            addFriendError = "Nobody on StarGaze has the username \(name)."
        } catch FollowError.cannotFollowSelf {
            addFriendError = "That's your own username."
        } catch FollowError.notSignedUp {
            addFriendError = "Your profile isn't set up yet. Check your connection and try again."
        } catch {
            addFriendError = "Couldn't add \(name). Check your connection and try again."
        }
    }

    private func fetch() async {
        do {
            let fetched = try await dataSource.fetchCaptures()
            captures = fetched.sorted { $0.date > $1.date }
            let remoteMine = try? await dataSource.fetchMyCaptures()
            me = dataSource.currentUser ?? Self.fallbackMe
            myCaptures = Self.myCaptures(remote: remoteMine, local: localFinds(), me: me)
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            // The view went away or the refresh was cancelled; keep what we have.
        } catch {
            errorMessage = "Couldn't load your friends' finds. Check your connection and try again."
        }
    }
}
