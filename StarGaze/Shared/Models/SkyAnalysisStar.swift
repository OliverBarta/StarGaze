//
//  SkyAnalysisStar.swift
//  StarGaze
//

import Foundation

/// One of the target constellation's brightest stars, given to Gemini as context.
nonisolated struct SkyAnalysisStar: Equatable, Sendable {
    /// Proper name if it has a well-known one (e.g. "Betelgeuse"), otherwise nil.
    let name: String?
    /// Visual magnitude (lower is brighter).
    let magnitude: Double
}
