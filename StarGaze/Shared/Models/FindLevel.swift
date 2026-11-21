//
//  FindLevel.swift
//  StarGaze
//

import Foundation

/// How well a find was confirmed by its sky photo.
nonisolated enum FindLevel: String, Codable, CaseIterable, Sendable {
    /// Night sky, not overcast, at least 3 stars visible. Double points and a gold stamp.
    case spotted
    /// Everything else: bright city sky, no camera, or a bad photo. Base points.
    case located

    /// The one rule for levels. No analysis (no camera, Gemini failed) means located.
    init(analysis: SkyAnalysis?) {
        if let analysis,
           analysis.isNightSky,
           analysis.cloudCover != .overcast,
           analysis.estimatedVisibleStars >= 3 {
            self = .spotted
        } else {
            self = .located
        }
    }

    var label: String {
        switch self {
        case .spotted: "Spotted"
        case .located: "Located"
        }
    }
}
