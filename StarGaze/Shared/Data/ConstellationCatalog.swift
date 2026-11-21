//
//  ConstellationCatalog.swift
//  StarGaze
//

import SwiftUI

/// Local constellation data, looked up by constellation name.
protocol ConstellationCatalog {
    /// The constellation's image, or nil if there isn't one. Matching ignores case and surrounding whitespace.
    func image(for constellationName: String) -> Image?
}
