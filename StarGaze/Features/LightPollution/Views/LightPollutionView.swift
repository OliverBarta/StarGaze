//
//  LightPollutionView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct LightPollutionView: View {
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1

    // Gesture values from the previous update, so pan and pinch can each
    // apply their change incrementally and run at the same time.
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    private let baseSpacing: CGFloat = 40
    private let scaleRange: ClosedRange<CGFloat> = 0.25...8

    var body: some View {
        Canvas { context, size in
            let spacing = baseSpacing * scale
            var path = Path()

            var x = offset.width.truncatingRemainder(dividingBy: spacing) - spacing
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y = offset.height.truncatingRemainder(dividingBy: spacing) - spacing
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(pan)
        .simultaneousGesture(zoom)
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                offset.width += value.translation.width - lastTranslation.width
                offset.height += value.translation.height - lastTranslation.height
                lastTranslation = value.translation
            }
            .onEnded { _ in
                lastTranslation = .zero
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = min(max(scale * value.magnification / lastMagnification, scaleRange.lowerBound), scaleRange.upperBound)
                let ratio = newScale / scale
                // Keep the point under the pinch fixed on screen while zooming.
                let anchor = value.startLocation
                offset.width = anchor.x - (anchor.x - offset.width) * ratio
                offset.height = anchor.y - (anchor.y - offset.height) * ratio
                scale = newScale
                lastMagnification = value.magnification
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }
}

#Preview {
    LightPollutionView()
}
