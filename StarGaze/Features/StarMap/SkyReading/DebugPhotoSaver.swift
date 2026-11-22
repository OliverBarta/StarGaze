#if DEBUG
import Photos
import UIKit
import UniformTypeIdentifiers

/// DEBUG builds only (running from Xcode): saves every sky photo to the Photos library (add-only
/// access) so we can see what the camera actually captured. Two images per shot:
/// 1. the original photo, full size, with exposure, ISO and motion in its EXIF;
/// 2. the exact JPEG sent to Gemini (same downscale and compression), to see what Gemini sees.
/// Release builds never save anything.
enum DebugPhotoSaver {
    static func save(_ photo: SkyPhoto, geminiImage: UIImage) async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { return }
        if let original = await originalJPEG(for: photo) {
            await add(original, what: "sky photo")
        }
        if let sent = await geminiJPEG(for: geminiImage) {
            await add(sent, what: "Gemini copy")
        }
    }

    private static func add(_ data: Data, what: String) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            print("⚠️ Couldn't save the \(what): \(error)")
        }
    }

    /// Exactly what `GeminiService` uploads: same maximum size and JPEG settings.
    @concurrent
    private nonisolated static func geminiJPEG(for image: UIImage) async -> Data? {
        image.jpegData(maxDimension: GeminiService.uploadMaxDimension)
    }

    @concurrent
    private nonisolated static func originalJPEG(for photo: SkyPhoto) async -> Data? {
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
