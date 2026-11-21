//
//  CaptureCardContent.swift
//  StarGaze
//

import SwiftUI

/// Feature-neutral input for `CaptureCardView`. Each feature maps its own model into this.
struct CaptureCardContent {
    var constellationName: String
    var locationName: String
    var date: Date
    var image: Image?
    var rarity: Rarity
    var points: Int
}
