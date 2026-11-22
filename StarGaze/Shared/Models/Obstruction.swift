//
//  Obstruction.swift
//  StarGaze
//

import Foundation

/// Something in the photo blocking or washing out the sky. Raw values match Gemini's JSON.
nonisolated enum Obstruction: String, Codable, CaseIterable, Sendable {
    case trees
    case buildings
    case streetlight
    case moonGlare = "moon_glare"
    /// Fog, haze or smoke.
    case haze
    /// Motion blur or out of focus.
    case blur
    /// Smudged, fogged or partly covered lens (e.g. a finger).
    case lens
    case other
}
