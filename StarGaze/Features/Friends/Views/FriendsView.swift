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
                }
                .sheet(isPresented: $isShowingAddFriend) {
                    AddFriendView { username in
                        Task { await viewModel.addFriend(username: username) }
                    }
                    .presentationDetents([.medium])
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
}

#Preview("Feed, dark") {
    FriendsView()
        .preferredColorScheme(.dark)
}

#Preview("Feed, large text") {
    FriendsView()
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Empty") {
    FriendsView(viewModel: FriendsViewModel(dataSource: MockFriendsDataSource(captures: [])))
}

#Preview("Loading") {
    FriendsView(viewModel: FriendsViewModel(dataSource: MockFriendsDataSource(delay: .seconds(3600))))
}

#Preview("Error") {
    FriendsView(viewModel: FriendsViewModel(dataSource: MockFriendsDataSource(shouldFail: true)))
}
