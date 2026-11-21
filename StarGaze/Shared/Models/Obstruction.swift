//
//  Obstruction.swift
//  StarGaze
//

import Foundation

/// Something in the photo blocking or washing out the sky. Raw values match Gemini's JSON and the database.
nonisolated enum Obstruction: String, Codable, CaseIterable, Sendable {
    case trees
    case buildings
    case streetlight
    case moonGlare = "moon_glare"
    case other

    var label: String {
        switch self {
        case .trees: "Trees"
        case .buildings: "Buildings"
        case .streetlight: "Streetlight"
        case .moonGlare: "Moon glare"
        case .other: "Other"
        }
    }
}
