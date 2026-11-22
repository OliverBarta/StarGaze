import Foundation
import CoreGraphics
import ImageIO

/// One sky photo with its context, ready for analysis. Lives in memory only.
nonisolated struct SkyPhoto: @unchecked Sendable {
    let context: SkyShotContext
    let captured: CapturedSkyPhoto
    let motion: ShotMotion?

    /// How to rotate the sensor-oriented image for viewing, from gravity at the shutter.
    var displayOrientation: CGImagePropertyOrientation {
        guard let g = motion?.gravity else { return .right }
        if abs(g.y) >= abs(g.x) {
            return g.y <= 0 ? .right : .left  // portrait, or upside down
        }
        return g.x <= 0 ? .up : .down  // landscape with the top to the left, or to the right
    }

    /// One line for the DEBUG overlay.
    var debugSummary: String {
        var parts = [
            String(format: "%.2f s", captured.exposureSeconds),
            "ISO \(Int(captured.iso.rounded()))",
            "\(captured.image.width)×\(captured.image.height)",
            String(format: "FOV %.0f°", captured.fieldOfViewDegrees),
        ]
        if let motion {
            parts.append(String(format: "moved %.1f°/s", motion.maxRotationDegreesPerSecond))
        }
        return parts.joined(separator: " · ")
    }
}
