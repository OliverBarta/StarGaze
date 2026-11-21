//
//  ConstellationName.swift
//  StarGaze
//

import Foundation

/// The single rule for matching constellation names across the app.
enum ConstellationName {
    /// Lowercased, trimmed, with runs of whitespace collapsed to one space.
    /// " Ursa  Major " → "ursa major".
    static func normalizedKey(for name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
