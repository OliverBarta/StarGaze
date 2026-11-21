//
//  StarView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct StarView: View {
    var body: some View {
        SkyScreen()
    }
}

#Preview {
    StarView()
        .environment(DiscoveryStore())
}
