//
//  ProgressView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-21.
//

import SwiftUI

/// Full-screen loading screen: the app mark over a night-sky gradient, with a spinner.
///
/// This shadows `SwiftUI.ProgressView` inside the module, so write `SwiftUI.ProgressView`
/// wherever you want the system spinner or progress bar.
struct ProgressView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: Metrics.xLarge) {
            VStack(spacing: Metrics.small) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
                Text("StarGaze")
                    .font(.largeTitle.bold())
            }

            SwiftUI.ProgressView(message)
                .controlSize(.large)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [.black, .indigo], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    ProgressView()
}
