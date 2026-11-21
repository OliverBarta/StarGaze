//
//  AssetConstellationCatalog.swift
//  StarGaze
//

import SwiftUI
import UIKit

/// Loads constellation images from the asset catalog.
/// Naming convention: "constellation-" + the lowercased name with spaces as hyphens,
/// e.g. "Ursa Major" → "constellation-ursa-major".
struct AssetConstellationCatalog: ConstellationCatalog {
    func image(for constellationName: String) -> Image? {
        UIImage(named: Self.assetName(for: constellationName)).map(Image.init(uiImage:))
    }

    static func assetName(for constellationName: String) -> String {
        let key = ConstellationName.normalizedKey(for: constellationName)
        return "constellation-" + key.replacingOccurrences(of: " ", with: "-")
    }
}
