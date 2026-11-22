//
//  SkyAnalysisContext.swift
//  StarGaze
//

import Foundation

/// What the app already knows about a live sky photo, sent to Gemini with the image.
/// Library photos have no context.
nonisolated struct SkyAnalysisContext: Equatable, Sendable {
    /// The constellation the phone was aimed at, e.g. "Orion".
    let constellationName: String
    /// Its brightest stick-figure stars, brightest first.
    let brightestStars: [SkyAnalysisStar]
    /// How many stars the on-device detector found in the photo, if detection ran.
    let detectedStars: Int?

    /// The context paragraph added to the prompt.
    var promptText: String {
        let stars = brightestStars.map { star in
            let magnitude = String(format: "magnitude %.1f", star.magnitude)
            return star.name.map { "\($0) (\(magnitude))" } ?? magnitude
        }
        var lines = [
            "Context from the phone's sensors: the camera was aimed at the constellation \(constellationName).",
        ]
        if !stars.isEmpty {
            lines.append("Its brightest stars are: \(stars.joined(separator: ", ")).")
        }
        if let detectedStars {
            lines.append("The phone's own star detector found \(detectedStars) star-like points in the photo.")
        }
        lines.append("The constellation should be roughly centred in the frame, but the photo may be rotated.")
        return lines.joined(separator: " ")
    }
}
