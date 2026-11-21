/// Where the sky photo is, for the overlay.
nonisolated enum SkyPhotoPhase: Equatable, Sendable {
    case idle
    case countdown(Int)
    case shooting
    case analyzing
}
