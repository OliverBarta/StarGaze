//
//  GeminiError.swift
//  StarGaze
//

import Foundation

/// Gemini failures, with messages that are safe to show to players.
nonisolated enum GeminiError: LocalizedError, Equatable, Sendable {
    case offline
    case rateLimited
    case unreadableImage
    case badResponse
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .offline:
            "You're offline. Check your connection and try again."
        case .rateLimited:
            "Gemini is busy right now. Wait a minute and try again."
        case .unreadableImage:
            "That photo couldn't be read. Try a different one."
        case .badResponse:
            "Gemini sent back an answer we couldn't understand. Try again."
        case .server(let status):
            "Gemini couldn't handle the request (error \(status)). Try again later."
        }
    }
}
