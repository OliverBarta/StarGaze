//
//  ProfilePictureView.swift
//  StarGaze
//

import SwiftUI

/// The signed-in user's picture, or a neutral person symbol if there isn't one.
struct ProfilePictureView: View {
    let url: URL?
    var size: CGFloat = 28

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size * scale, height: size * scale)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Metrics.medium) {
        ProfilePictureView(url: nil)
        ProfilePictureView(url: nil, size: 72)
    }
    .padding()
}
