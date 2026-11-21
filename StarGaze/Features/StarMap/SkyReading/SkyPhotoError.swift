/// Why a sky photo couldn't be taken. The find is collected regardless.
nonisolated enum SkyPhotoError: Error, Sendable {
    case noCamera
    case configurationFailed
    case sessionDidNotStart
    case captureFailed
    case timedOut
}
