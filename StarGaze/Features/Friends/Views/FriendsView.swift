//
//  FriendsView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct FriendsView: View {
    @State private var viewModel: FriendsViewModel
    @State private var isShowingAddFriend = false

    init(viewModel: FriendsViewModel = FriendsViewModel(dataSource: MockFriendsDataSource())) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Friends")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add Friend", systemImage: "person.badge.plus") {
                            isShowingAddFriend = true
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileButton()
                    }
                }
                .sheet(isPresented: $isShowingAddFriend) {
                    AddFriendView { username in
                        Task { await viewModel.addFriend(username: username) }
                    }
                    .presentationDetents([.medium])
                }
                .alert(
                    "Couldn't Add Friend",
                    isPresented: Binding(
                        get: { viewModel.addFriendError != nil },
                        set: { if !$0 { viewModel.addFriendError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(viewModel.addFriendError ?? "")
                }
                .task {
                    await viewModel.load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage, viewModel.captures.isEmpty {
            FriendsErrorView(message: errorMessage) {
                Task { await viewModel.load() }
            }
        } else if !viewModel.hasLoaded {
            FriendsLoadingView()
        } else if viewModel.captures.isEmpty {
            ScrollView {
                FriendsEmptyView()
                    .containerRelativeFrame([.horizontal, .vertical])
            }
            .refreshable {
                await viewModel.refresh()
            }
        } else {
            feed
        }
    }

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xLarge) {
                if !viewModel.standings.isEmpty {
                    LeaderboardSection(standings: viewModel.standings)
                }

                VStack(alignment: .leading, spacing: Metrics.small) {
                    Text("Recent finds")
                        .font(.title3.bold())
                    LazyVStack(spacing: Metrics.large) {
                        ForEach(viewModel.captures) { capture in
                            CaptureCardView(content: viewModel.cardContent(for: capture)) {
                                FriendCaptureHeader(friend: capture.friend)
                            }
                        }
                    }
                }
            }
            .padding(Metrics.large)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

#Preview("Feed") {
    FriendsView()
        .environment(AuthService.preview(user: .preview))
}

#Preview("Feed, dark") {
    FriendsView()
        .preferredColorScheme(.dark)
        .environment(AuthService.preview(user: .preview))
}

#Preview("Feed, large text") {
    FriendsView()
        .environment(\.dynamicTypeSize, .accessibility2)
        .environment(AuthService.preview(user: .preview))
}

#Preview("Empty") {
    FriendsView(viewModel: FriendsViewModel(dataSource: MockFriendsDataSource(captures: [])))
        .environment(AuthService.preview(user: .preview))
}

#Preview("Loading") {
    FriendsView(viewModel: FriendsViewModel(dataSource: MockFriendsDataSource(delay: .seconds(3600))))
        .environment(AuthService.preview(user: .preview))
}

#Preview("Error") {
    FriendsView(viewModel: FriendsViewModel(dataSource: MockFriendsDataSource(shouldFail: true)))
        .environment(AuthService.preview(user: .preview))
}
