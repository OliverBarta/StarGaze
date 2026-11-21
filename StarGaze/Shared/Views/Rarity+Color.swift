//
//  Rarity+Color.swift
//  StarGaze
//

import SwiftUI
import UIKit

extension Rarity {
    /// The one place rarity colors are defined. Use for symbols and text only.
    var color: Color {
        switch self {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: Self.gold
        }
    }

    /// Darker gold on light backgrounds, brighter gold on dark ones, so it stays readable.
    private nonisolated static let gold = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 0.949, green: 0.757, blue: 0.306, alpha: 1) // #F2C14E
        } else {
            UIColor(red: 0.639, green: 0.408, blue: 0.0, alpha: 1) // #A36800
        }
    })
}
