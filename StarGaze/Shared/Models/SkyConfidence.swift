//
//  SkyConfidence.swift
//  StarGaze
//

import Foundation

/// How sure Gemini is about its sky analysis. Raw values match the `sky_readings` table.
nonisolated enum SkyConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    var label: String {
        rawValue.capitalized
    }
}
