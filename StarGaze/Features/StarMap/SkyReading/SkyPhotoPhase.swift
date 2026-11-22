/// Where the sky photo is, for the overlay. Analysis runs separately (`SkyPhotoSession.isAnalyzing`)
/// so it never blocks the next capture.
nonisolated enum SkyPhotoPhase: Equatable, Sendable {
    case idle
    case countdown(Int)
    case shooting
}
