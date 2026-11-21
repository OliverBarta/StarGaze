//
//  JSONConstellationCatalog.swift
//  StarGaze
//

import SwiftUI
import UIKit

/// Loads constellation images from the PNGs listed in constellation-info.json.
/// The JSON's `image` is a source path ("Shared/Data/Constellation Images/PNG/constellation_orion.png"),
/// but resources are copied flat into the bundle, so only the file name is used to find it.
struct JSONConstellationCatalog: ConstellationCatalog {
    func image(for constellationName: String) -> Image? {
        let key = ConstellationName.normalizedKey(for: constellationName)
        if let cached = Self.cache[key] { return Image(uiImage: cached) }
        guard let path = Self.imagePaths[key],
              let url = Self.bundleURL(forImagePath: path),
              let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        Self.cache[key] = uiImage
        return Image(uiImage: uiImage)
    }

    /// Normalized constellation name → the `image` path from the JSON.
    private static let imagePaths: [String: String] = {
        var paths: [String: String] = [:]
        for info in ConstellationInfoCatalog.byName.values where !info.image.isEmpty {
            paths[ConstellationName.normalizedKey(for: info.name)] = info.image
        }
        return paths
    }()

    /// Decoded images, so each PNG is only read from disk once.
    private static var cache: [String: UIImage] = [:]

    static func bundleURL(forImagePath path: String) -> URL? {
        let file = URL(fileURLWithPath: path)
        return Bundle.main.url(forResource: file.deletingPathExtension().lastPathComponent,
                               withExtension: file.pathExtension)
    }
}
