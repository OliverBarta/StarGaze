//
//  SkyBand.swift
//  StarGaze
//

import Foundation

/// A plain-language light-pollution class, shown before the Bortle number.
nonisolated enum SkyBand: String, Codable, CaseIterable, Sendable {
    case city
    case brightSuburban = "bright_suburban"
    case suburban
    case rural
    case dark

    init(bortle: Int) {
        switch bortle {
        case ...2: self = .dark
        case 3...4: self = .rural
        case 5...6: self = .suburban
        case 7: self = .brightSuburban
        default: self = .city
        }
    }

    var label: String {
        switch self {
        case .city: "City sky"
        case .brightSuburban: "Bright suburban sky"
        case .suburban: "Suburban sky"
        case .rural: "Rural sky"
        case .dark: "Dark sky"
        }
    }
}
