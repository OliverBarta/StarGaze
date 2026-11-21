//
//  CaptureImageView.swift
//  StarGaze
//

import SwiftUI

struct CaptureImageView: View {
    let image: Image?

    var body: some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color(.tertiarySystemFill)
            .overlay {
                Image(systemName: "moon.stars")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    CaptureImageView(image: nil)
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.imageCornerRadius, style: .continuous))
        .padding()
}
