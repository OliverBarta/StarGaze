//
//  FindLevel.swift
//  StarGaze
//

import Foundation

/// How well a find was confirmed by its sky photo.
nonisolated enum FindLevel: String, Codable, CaseIterable, Sendable {
    /// The reading counts toward the map and Gemini could see the constellation's pattern.
    /// Double points and a gold badge.
    case spotted
    /// Everything else: bright city sky, no camera, or a bad photo. Base points.
    case located

    /// The one rule for levels. No analysis (no camera, Gemini failed) means located.
    init(reliable: Bool, analysis: SkyAnalysis?) {
        self = reliable && analysis?.targetPatternVisible == true ? .spotted : .located
    }

    var label: String {
        switch self {
        case .spotted: "Spotted"
        case .located: "Located"
        }
    }
}
