import Foundation

/// What happens to a capture once its sky photo has been checked, and the toast that says so.
nonisolated enum CaptureVerdict: Equatable, Sendable {
    /// Don't collect: the photo wasn't the sky.
    case reject(toast: String)
    /// Collect, with this toast; `spotted` earns the 2× upgrade.
    case collect(toast: String, spotted: Bool)

    /// - nil reading (no camera, or the photo failed): collect.
    /// - Gemini sure it isn't the sky, or the phone was lowered during the shot: don't collect.
    /// - Gemini offline or timed out: collect, the reading just doesn't count.
    /// - Other problems (clouds, streetlight, phone moved…): collect, and say why the reading doesn't count.
    static func decide(_ reading: SkyPhotoReading?, name: String) -> CaptureVerdict {
        let collected = "✦ Collected \(name)"
        guard let reading else { return .collect(toast: collected, spotted: false) }
        if reading.isConfidentlyNotSky {
            return .reject(toast: "Not collected · That didn't look like the sky")
        }
        if reading.wasAimedTooLow {
            return .reject(toast: "Not collected · Point up at the sky")
        }
        if reading.reliable {
            return .collect(toast: "\(collected) · \(reading.band.label) (Bortle \(reading.bortle))",
                            spotted: reading.level == .spotted)
        }
        if reading.issues.contains(.unchecked) {
            return .collect(toast: collected, spotted: false)
        }
        let reasons = reading.blockingIssues.map(\.label).joined(separator: ", ")
        return .collect(toast: "\(collected) · Sky reading not counted: \(reasons)", spotted: false)
    }
}
