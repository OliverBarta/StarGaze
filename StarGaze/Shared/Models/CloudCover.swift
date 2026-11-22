//
//  CloudCover.swift
//  StarGaze
//

import Foundation

/// How much of the photographed sky is covered by cloud. Raw values match Gemini's JSON.
nonisolated enum CloudCover: String, Codable, CaseIterable, Sendable {
    case none
    case partial
    case overcast
}
