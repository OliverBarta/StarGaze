//
//  SkyReadingSource.swift
//  StarGaze
//

import Foundation

/// Where a reading's photo came from. Only camera readings can go on the map.
nonisolated enum SkyReadingSource: String, Codable, Sendable {
    case camera
    case library
}
