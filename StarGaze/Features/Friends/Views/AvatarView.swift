//
//  AvatarView.swift
//  StarGaze
//

import SwiftUI

/// A friend's photo. Holds its frame while loading so nearby text doesn't jump,
/// and collapses to nothing if the photo fails to load.
struct AvatarView: View {
    let url: URL
    var size: CGFloat = 32

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var scaledSize: CGFloat {
        size * scale
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: scaledSize, height: scaledSize)
                    .clipShape(Circle())
            case .empty:
                Color.clear
                    .frame(width: scaledSize, height: scaledSize)
            default:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Failed load collapses") {
    HStack(spacing: Metrics.small) {
        AvatarView(url: URL(filePath: "/missing-avatar.jpg"))
        Text("Maya Chen")
    }
    .padding()
}
