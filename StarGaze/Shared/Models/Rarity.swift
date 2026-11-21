//
//  Rarity.swift
//  StarGaze
//

import Foundation

/// How hard a constellation is to find. Colors live in `Rarity+Color.swift` so this stays Foundation-only.
enum Rarity: CaseIterable {
    case common
    case uncommon
    case rare
    case legendary

    var label: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .legendary: "Legendary"
        }
    }

    /// A quiet progression from outline to filled, with a star for the rarest.
    var symbol: String {
        switch self {
        case .common: "circle"
        case .uncommon: "circle.lefthalf.filled"
        case .rare: "circle.fill"
        case .legendary: "star.fill"
        }
    }

    var points: Int {
        switch self {
        case .common: 10
        case .uncommon: 25
        case .rare: 50
        case .legendary: 100
        }
    }

    /// Temporary hardcoded lookup until rarity comes from real data. Unknown names are uncommon.
    /// Matching ignores case and surrounding whitespace.
    static func forConstellation(_ name: String) -> Rarity {
        lookup[ConstellationName.normalizedKey(for: name)] ?? .uncommon
    }

    private static let lookup: [String: Rarity] = [
        // Bright and easy to spot, even from the city.
        "orion": .common,
        "ursa major": .common,
        "cassiopeia": .common,
        "cygnus": .common,
        "scorpius": .common,
        "leo": .common,
        // Recognizable with a little effort.
        "lyra": .uncommon,
        "pegasus": .uncommon,
        "andromeda": .uncommon,
        "perseus": .uncommon,
        "auriga": .uncommon,
        "gemini": .uncommon,
        "taurus": .uncommon,
        "ursa minor": .uncommon,
        "delphinus": .uncommon,
        // Faint or easily confused; needs dark skies.
        "cepheus": .rare,
        "draco": .rare,
        "lacerta": .rare,
        "triangulum": .rare,
        "vulpecula": .rare,
        "sagitta": .rare,
        // Very faint, few bright stars.
        "camelopardalis": .legendary,
        "lynx": .legendary,
        "monoceros": .legendary,
        "leo minor": .legendary,
        "canes venatici": .legendary,
    ]
}
