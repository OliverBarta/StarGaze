//
//  SkyReadingIssue.swift
//  StarGaze
//

import Foundation

/// Something that makes a sky reading unreliable (it won't count toward the map) or less certain.
/// Gemini's checks come from `issues(from:)`; the device checks (twilight, motion, Moon) are added
/// when the reading is combined.
nonisolated enum SkyReadingIssue: String, Codable, CaseIterable, Sendable {
    // From Gemini
    case notSky = "not_sky"
    case clouds
    case partialClouds = "partial_clouds"
    case brightLight = "bright_light"
    case moonGlare = "moon_glare"
    case haze
    case blur
    case lens
    // From the device
    case twilight
    case phoneMoved = "phone_moved"
    case moonBright = "moon_bright"

    /// True: the reading is unreliable and won't count toward the map.
    /// False: the reading is kept with lower confidence.
    var isBlocking: Bool {
        switch self {
        case .partialClouds, .moonBright: false
        default: true
        }
    }

    var label: String {
        switch self {
        case .notSky: "Not a sky photo"
        case .clouds: "Clouds"
        case .partialClouds: "Some clouds"
        case .brightLight: "Streetlight in frame"
        case .moonGlare: "Moon glare"
        case .haze: "Haze or fog"
        case .blur: "Blurry photo"
        case .lens: "Smudged or covered lens"
        case .twilight: "Twilight"
        case .phoneMoved: "Phone moved"
        case .moonBright: "Moon brightening the sky"
        }
    }

    /// Gemini's quality verdict as issues, most important first.
    static func issues(from analysis: SkyAnalysis) -> [SkyReadingIssue] {
        var issues: [SkyReadingIssue] = []
        if !analysis.isNightSky { issues.append(.notSky) }
        switch analysis.cloudCover {
        case .overcast: issues.append(.clouds)
        case .partial: issues.append(.partialClouds)
        case .none: break
        }
        let obstructions = Set(analysis.obstructions)
        if obstructions.contains(.streetlight) { issues.append(.brightLight) }
        if obstructions.contains(.moonGlare) { issues.append(.moonGlare) }
        if obstructions.contains(.haze) { issues.append(.haze) }
        if obstructions.contains(.blur) { issues.append(.blur) }
        if obstructions.contains(.lens) { issues.append(.lens) }
        return issues.sorted { $0.isBlocking && !$1.isBlocking }
    }
}
