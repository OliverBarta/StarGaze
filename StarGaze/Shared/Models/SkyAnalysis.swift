//
//  SkyAnalysis.swift
//  StarGaze
//

import Foundation

/// Gemini's quality check of one sky photo. It never identifies constellations;
/// it only says whether the photo is a usable measurement of the night sky.
nonisolated struct SkyAnalysis: Codable, Equatable, Sendable {
    var isNightSky: Bool
    var cloudCover: CloudCover
    var obstructions: [Obstruction]
    var estimatedVisibleStars: Int
    /// Bortle-like: 1 = pristine dark sky, 9 = inner-city sky.
    var skyBrightness: Int
    var confidence: SkyConfidence
    /// The target constellation's stick-figure pattern can be recognised in the photo.
    /// Always false without context (library photos).
    var targetPatternVisible: Bool
    var reason: String

    /// Decodes Gemini's JSON and keeps every value in range.
    /// Throws `GeminiError.badResponse` if the JSON doesn't match the schema.
    static func validated(fromJSON data: Data) throws -> SkyAnalysis {
        guard var analysis = try? JSONDecoder().decode(SkyAnalysis.self, from: data) else {
            throw GeminiError.badResponse
        }
        analysis.estimatedVisibleStars = max(0, analysis.estimatedVisibleStars)
        analysis.skyBrightness = min(9, max(1, analysis.skyBrightness))
        var unique: [Obstruction] = []
        for obstruction in analysis.obstructions where !unique.contains(obstruction) {
            unique.append(obstruction)
        }
        analysis.obstructions = unique
        analysis.reason = analysis.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if analysis.reason.isEmpty {
            analysis.reason = "No reason given."
        }
        return analysis
    }
}

#if DEBUG
extension SkyAnalysis {
    static let previewSpotted = SkyAnalysis(
        isNightSky: true,
        cloudCover: .partial,
        obstructions: [.trees],
        estimatedVisibleStars: 14,
        skyBrightness: 5,
        confidence: .medium,
        targetPatternVisible: true,
        reason: "Night sky with a dozen or so stars visible above a tree line; some thin cloud in one corner."
    )

    static let previewLocated = SkyAnalysis(
        isNightSky: true,
        cloudCover: .overcast,
        obstructions: [.streetlight, .buildings],
        estimatedVisibleStars: 0,
        skyBrightness: 8,
        confidence: .high,
        targetPatternVisible: false,
        reason: "Uniform orange cloud lit by streetlights; no stars visible."
    )
}
#endif
