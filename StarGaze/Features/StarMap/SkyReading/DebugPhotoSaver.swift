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

    /// The detector's working image, stretched so faint stars show, with a circle around each
    /// accepted star. Sensor orientation (landscape), like the detector sees it.
    static func saveAnnotated(_ image: LuminanceImage, detection: StarDetectionResult) async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized,
              let data = await annotatedJPEG(image, detection: detection) else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }

    @concurrent
    private nonisolated static func annotatedJPEG(_ image: LuminanceImage, detection: StarDetectionResult) async -> Data? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let base = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stretch = max(30 * detection.noiseSigma, 1e-6)
        let rowBytes = context.bytesPerRow
        for y in 0..<h {
            for x in 0..<w {
                let v = (image.pixels[y * w + x] - detection.backgroundMedian) / stretch
                let gray = UInt8(min(max(0.15 + v, 0), 1) * 255)
                // CGContext rows start at the top here (we write memory directly)
                let p = base + y * rowBytes + x * 4
                p[0] = gray
                p[1] = gray
                p[2] = gray
            }
        }
        context.setStrokeColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        context.setLineWidth(2)
        for star in detection.stars {
            // drawing uses a bottom-left origin
            context.strokeEllipse(in: CGRect(x: CGFloat(star.x) - 8, y: CGFloat(h) - CGFloat(star.y) - 8,
                                             width: 16, height: 16))
        }
        guard let cgImage = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let exif: [String: Any] = [
            kCGImagePropertyExifUserComment as String:
                "StarGaze detection: \(detection.starCount) stars, rejected \(detection.rejections)",
        ]
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyExifDictionary as String: exif] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
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
