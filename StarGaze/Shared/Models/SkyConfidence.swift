//
//  SkyConfidence.swift
//  StarGaze
//

import Foundation

/// How sure Gemini is about its sky analysis. Raw values match Gemini's JSON.
nonisolated enum SkyConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}
