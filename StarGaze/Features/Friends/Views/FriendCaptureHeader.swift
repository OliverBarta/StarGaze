//
//  FriendCaptureHeader.swift
//  StarGaze
//

import SwiftUI

/// Who made the capture, shown in the shared card's header slot.
struct FriendCaptureHeader: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: Metrics.small) {
            if let avatarURL = friend.avatarURL {
                AvatarView(url: avatarURL, size: 28)
            }
            Text(friend.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

#Preview("Friend without avatar") {
    let capture = MockFriendsDataSource.sampleCaptures[1]
    ScrollView {
        CaptureCardView(content: capture.cardContent(using: AssetConstellationCatalog())) {
            FriendCaptureHeader(friend: capture.friend)
        }
        .padding(Metrics.large)
    }
    .background(Color(.systemGroupedBackground))
}
