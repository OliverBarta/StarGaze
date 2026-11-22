//
//  SupabaseService.swift
//  StarGaze
//

import Foundation
import Observation

/// The signed-in user's row in the Supabase `profiles` table.
struct SocialProfile: Codable, Hashable {
    let id: String
    var username: String
    var displayName: String?
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}

enum SupabaseError: Error {
    case http(status: Int, code: String?, message: String?)

    /// A Postgres unique-constraint or primary-key violation (PostgREST answers 409).
    var isConflict: Bool {
        if case let .http(status, code, _) = self { return status == 409 || code == "23505" }
        return false
    }
}

/// Profiles, follows and shared captures, through Supabase's REST API (PostgREST).
/// Requests carry the user's Auth0 access token (Supabase Third-Party Auth), and the
/// row-level security policies in `supabase/schema.sql` decide what each user can see.
@Observable
final class SupabaseService {
    /// One row of the `feed` view: a capture by someone the user follows.
    struct FeedItem: Decodable {
        let id: UUID
        let constellationName: String
        let locationName: String
        let capturedAt: Date
        let userID: String
        let username: String
        let displayName: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case id, username
            case constellationName = "constellation_name"
            case locationName = "location_name"
            case capturedAt = "captured_at"
            case userID = "user_id"
            case displayName = "display_name"
            case avatarURL = "avatar_url"
        }
    }

    /// Set once `syncProfile(for:)` succeeds.
    private(set) var profile: SocialProfile?

    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let apiKey: String
    @ObservationIgnored private let accessToken: () async throws -> String

    init(
        baseURL: URL = URL(string: Secrets.supabaseURL)!,
        apiKey: String = Secrets.supabaseKey,
        accessToken: @escaping () async throws -> String
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.accessToken = accessToken
    }

    // MARK: Profile

    /// Loads the user's profile, creating it with a generated username on first sign-in,
    /// and keeps the display name and picture in step with Auth0.
    func syncProfile(for user: AppUser) async throws {
        let existing: [SocialProfile] = try await request("GET", "profiles", query: ["id": "eq.\(user.id)", "select": "*"])
        let avatar = user.pictureURL?.absoluteString

        if let current = existing.first {
            guard current.displayName != user.displayName || current.avatarURL != avatar else {
                profile = current
                return
            }
            let updated: [SocialProfile] = try await request(
                "PATCH", "profiles", query: ["id": "eq.\(user.id)"],
                body: ["display_name": user.displayName, "avatar_url": avatar] as [String: String?],
                prefer: "return=representation")
            profile = updated.first ?? current
            return
        }

        let base = Self.baseUsername(for: user)
        var username = base
        for attempt in 1...5 {
            do {
                // `id` defaults to the JWT's `sub` in the database.
                let created: [SocialProfile] = try await request(
                    "POST", "profiles",
                    body: ["username": username, "display_name": user.displayName, "avatar_url": avatar] as [String: String?],
                    prefer: "return=representation")
                profile = created.first
                return
            } catch let error as SupabaseError where error.isConflict && attempt < 5 {
                // Username taken; try with a random suffix.
                username = "\(base.prefix(15))_\(Int.random(in: 100...9999))"
            }
        }
    }

    /// A valid username (`^[a-z0-9_]{3,20}$`) from the Auth0 nickname, email or name.
    private static func baseUsername(for user: AppUser) -> String {
        let emailName = user.email?.split(separator: "@").first.map(String.init)
        let source: String = user.nickname ?? emailName ?? user.name ?? ""
        var allowed = ""
        for character in source.lowercased() {
            let isValid = character.isASCII && (character.isLetter || character.isNumber)
            allowed.append(isValid ? character : "_")
        }
        var name = String(allowed.prefix(20))
        if name.count < 3 { name = "stargazer" }
        return name
    }

    // MARK: Follows

    /// The user ID for a username, or nil if nobody has it.
    func userID(forUsername username: String) async throws -> String? {
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await request("GET", "profiles", query: ["username": "eq.\(username)", "select": "id"])
        return rows.first?.id
    }

    /// Follows a user. Following someone you already follow is not an error.
    func follow(userID: String) async throws {
        do {
            try await send("POST", "follows", body: ["followee_id": userID], prefer: "return=minimal")
        } catch let error as SupabaseError where error.isConflict {
            // Already following.
        }
    }

    // MARK: Captures

    /// Uploads discoveries. Ones already uploaded are skipped by the unique
    /// (user, constellation, time) constraint, so it's safe to send everything again.
    func uploadCaptures(_ discoveries: [DiscoveryStore.Discovery]) async throws {
        guard profile != nil, !discoveries.isEmpty else { return }
        let rows = discoveries.map {
            ["constellation_name": $0.name, "location_name": $0.place, "captured_at": Self.formatDate($0.date)]
        }
        try await send(
            "POST", "captures", query: ["on_conflict": "user_id,constellation_name,captured_at"],
            body: rows, prefer: "resolution=ignore-duplicates,return=minimal")
    }

    /// Captures by everyone the user follows, newest first.
    func fetchFeed(limit: Int = 200) async throws -> [FeedItem] {
        try await request("GET", "feed", query: ["select": "*", "limit": "\(limit)"])
    }

    // MARK: Light readings

    /// Every row of `light_readings`, paged because Supabase caps each response at 1000 rows.
    func fetchLightReadings(pageSize: Int = 1000) async throws -> [LightReading] {
        var all: [LightReading] = []
        while true {
            let page: [LightReading] = try await request("GET", "light_readings", query: [
                "select": "coordinates,strength",
                "order": "id",
                "limit": "\(pageSize)",
                "offset": "\(all.count)",
            ])
            all += page
            if page.count < pageSize { return all }
        }
    }

    /// Adds one reading to the shared map. `coordinates` is a Postgres point "(lat,lon)".
    func insertLightReading(latitude: Double, longitude: Double, strength: Double) async throws {
        struct Row: Encodable {
            let coordinates: String
            let strength: Double
        }
        let row = Row(coordinates: "(\(latitude),\(longitude))", strength: min(1, max(0, strength)))
        try await send("POST", "light_readings", body: row, prefer: "return=minimal")
    }

    // MARK: Requests

    private func request<Response: Decodable>(
        _ method: String, _ path: String, query: [String: String] = [:],
        body: (any Encodable)? = nil, prefer: String? = nil
    ) async throws -> Response {
        let data = try await send(method, path, query: query, body: body, prefer: prefer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Self.parseDate(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unexpected date \(string)")
            }
            return date
        }
        return try decoder.decode(Response.self, from: data)
    }

    @discardableResult
    private func send(
        _ method: String, _ path: String, query: [String: String] = [:],
        body: (any Encodable)? = nil, prefer: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        let token = try await accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct ErrorBody: Decodable { let code: String?; let message: String? }
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            #if DEBUG
            if status == 401 { print("Supabase rejected the Auth0 token. \(Self.describe(token: token))") }
            #endif
            throw SupabaseError.http(status: status, code: body?.code, message: body?.message)
        }
        return data
    }

    // MARK: Dates

    nonisolated private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated private static let plainFormatter = ISO8601DateFormatter()

    /// Millisecond precision, so the same discovery always uploads the same timestamp.
    nonisolated private static func formatDate(_ date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    /// Postgres sends microseconds (`…:45.123456+00:00`); trim to milliseconds before parsing.
    nonisolated private static func parseDate(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return fractionalFormatter.date(from: trimmed) ?? plainFormatter.date(from: trimmed)
    }
}

#if DEBUG
extension SupabaseService {
    /// The header and a few claims of a JWT, for debugging auth setup. Never prints the signature.
    static func describe(token: String) -> String {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return "Not a signed JWT (\(parts.count) parts); sign out and back in." }
        func json(_ part: String) -> [String: Any] {
            var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: base64),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return object
        }
        let header = json(parts[0]), claims = json(parts[1])
        return "alg=\(header["alg"] ?? "-") kid=\(header["kid"] ?? "-") iss=\(claims["iss"] ?? "-") aud=\(claims["aud"] ?? "-") role=\(claims["role"] ?? "-")"
    }

    /// A service for previews. It never reaches the network.
    static func preview(profile: SocialProfile? = SocialProfile(id: "auth0|preview", username: "alex")) -> SupabaseService {
        let service = SupabaseService(baseURL: URL(string: "https://preview.invalid")!, apiKey: "") {
            throw URLError(.notConnectedToInternet)
        }
        service.profile = profile
        return service
    }
}
#endif
