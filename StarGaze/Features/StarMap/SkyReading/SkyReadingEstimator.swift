import Foundation

/// Turns one sky photo's measurements into a reading. Pure: no camera, network or UI.
///
/// The star count decides the Bortle class (fewer stars, brighter sky). Gemini is a quality filter
/// first; its own brightness guess only lowers confidence when it disagrees by 2+ classes.
/// Device checks: twilight and motion make the reading unreliable, a bright Moon lowers confidence.
nonisolated enum SkyReadingEstimator {
    struct Input: Sendable {
        var context: SkyShotContext
        var source: SkyReadingSource
        var deviceModel: String
        var exposureSeconds: Double
        var iso: Double
        var detection: StarDetectionResult?
        var analysis: SkyAnalysis?
        var device: SkyDeviceEvidence?
        var sky: SkyAstronomy
        var hasLocation: Bool
    }

    /// TODO(Part 5): compare against the catalog stars expected in frame instead of fixed count bands.
    static func bortle(detectedStars: Int) -> Int {
        for band in SkyReadingTuning.bortleForStarCount where detectedStars >= band.minStars {
            return band.bortle
        }
        return 9
    }

    static func reading(from input: Input) -> SkyPhotoReading {
        var issues = SkyReadingIssue.issues(from: input.analysis, device: input.device)
        if input.analysis == nil || input.detection == nil { issues.append(.unchecked) }
        if input.sky.sunAltitudeDeg > SkyReadingTuning.maxSunAltitudeDegrees { issues.append(.twilight) }
        if input.sky.moonIsUp && input.sky.moonIllumination > SkyReadingTuning.brightMoonIllumination {
            issues.append(.moonBright)
        }
        issues = issues.sorted { $0.isBlocking && !$1.isBlocking }

        let detected = input.detection?.starCount
        let bortle = bortle(detectedStars: detected ?? 0)
        let reliable = !issues.contains(where: \.isBlocking)

        return SkyPhotoReading(
            takenAt: input.context.takenAt,
            constellationID: input.context.constellationID,
            constellationName: input.context.constellationName,
            latitude: (input.context.latitude * 100).rounded() / 100,
            longitude: (input.context.longitude * 100).rounded() / 100,
            hasLocation: input.hasLocation,
            source: input.source,
            deviceModel: input.deviceModel,
            exposureSeconds: input.exposureSeconds,
            iso: input.iso,
            detectedStars: detected,
            relativeSkyGlow: input.detection.map { Double($0.relativeSkyGlow) },
            bortle: bortle,
            band: SkyBand(bortle: bortle),
            confidence: confidence(bortle: bortle, analysis: input.analysis, issues: issues),
            reliable: reliable,
            issues: issues,
            gemini: input.analysis,
            level: FindLevel(reliable: reliable, analysis: input.analysis),
            cameraElevationDegrees: input.device?.cameraElevationDegrees
        )
    }

    /// Starts high and steps down for each doubt; a bright Moon always means low.
    static func confidence(bortle: Int, analysis: SkyAnalysis?, issues: [SkyReadingIssue]) -> SkyConfidence {
        if issues.contains(.moonBright) { return .low }
        var doubts = 0
        if let analysis {
            if abs(analysis.skyBrightness - bortle) >= SkyReadingTuning.geminiDisagreementClasses { doubts += 1 }
            if analysis.confidence == .low { doubts += 1 }
        } else {
            doubts += 1
        }
        if issues.contains(.partialClouds) { doubts += 1 }
        switch doubts {
        case 0: return .high
        case 1: return .medium
        default: return .low
        }
    }
}
