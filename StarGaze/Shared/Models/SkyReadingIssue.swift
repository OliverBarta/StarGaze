//
//  SkyReadingIssue.swift
//  StarGaze
//

import Foundation

/// Something that makes a sky reading unreliable (it won't count toward the map) or less certain.
/// `issues(from:device:)` combines Gemini's checks with the phone's own evidence; twilight and the
/// Moon are added when the reading is combined.
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

    /// Gemini's quality verdict as issues, most important first. With device evidence (live
    /// captures) the phone's sensors win:
    /// - pointed upward: Gemini's "not a sky photo" only counts if it is highly confident;
    /// - blur comes mainly from the motion sensor ("Phone moved") and the detector's streak check;
    ///   when both say the shot was steady and sharp, Gemini's blur only counts if highly confident.
    static func issues(from analysis: SkyAnalysis?, device: SkyDeviceEvidence? = nil) -> [SkyReadingIssue] {
        var issues: [SkyReadingIssue] = []
        if let analysis {
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
        }

        if let device {
            let geminiSure = analysis?.confidence == .high
            if device.pointedAtSky && !geminiSure {
                issues.removeAll { $0 == .notSky }
            }
            if device.moved == true {
                issues.append(.phoneMoved)
            }
            if device.streaked == true {
                if !issues.contains(.blur) { issues.append(.blur) }
            } else if device.moved == false && device.streaked == false && !geminiSure {
                issues.removeAll { $0 == .blur }
            }
        }
        return issues.sorted { $0.isBlocking && !$1.isBlocking }
    }
}
