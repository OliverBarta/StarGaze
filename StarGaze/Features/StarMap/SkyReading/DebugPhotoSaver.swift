#if DEBUG
import Photos
import UniformTypeIdentifiers

/// DEBUG only: saves the full sky photo to the Photos library (add-only access) so exposure and
/// blur can be inspected. The exposure, ISO and motion are written into the photo's EXIF.
enum DebugPhotoSaver {
    static let defaultsKey = "StarGaze.debug.saveSkyPhotos"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static func save(_ photo: SkyPhoto) async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized,
              let data = await jpegData(for: photo) else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            print("⚠️ Couldn't save the sky photo: \(error)")
        }
    }

    @concurrent
    private nonisolated static func jpegData(for photo: SkyPhoto) async -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let exif: [String: Any] = [
            kCGImagePropertyExifExposureTime as String: photo.captured.exposureSeconds,
            kCGImagePropertyExifISOSpeedRatings as String: [Int(photo.captured.iso.rounded())],
            kCGImagePropertyExifUserComment as String: "StarGaze \(photo.context.constellationName): \(photo.debugSummary)",
        ]
        let properties: [String: Any] = [
            kCGImagePropertyOrientation as String: photo.displayOrientation.rawValue,
            kCGImageDestinationLossyCompressionQuality as String: 0.95,
            kCGImagePropertyExifDictionary as String: exif,
        ]
        CGImageDestinationAddImage(destination, photo.captured.image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
#endif
