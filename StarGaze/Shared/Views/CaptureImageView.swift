//
//  CaptureImageView.swift
//  StarGaze
//

import SwiftUI

struct CaptureImageView: View {
    let image: Image?

    /// The constellation PNGs' background colour, so the side borders blend into the image.
    private static let borderColor = Color(red: 11 / 255, green: 16 / 255, blue: 32 / 255)

    var body: some View {
        if let image {
            // Fit the whole (square) image and fill the leftover space with borders.
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.borderColor)
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
