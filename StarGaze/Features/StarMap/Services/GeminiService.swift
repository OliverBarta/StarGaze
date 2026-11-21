import UIKit

/// Talks to the Gemini REST API. Two jobs:
/// - `describe(constellation:)`: a short description for the info sheet (cached per constellation).
/// - `analyzeSky(_:)`: quality control for sky readings. It never identifies constellations;
///   identification is sensor-based.
final class GeminiService {
    private let model = "gemini-3.5-flash-lite"
    private static var cache: [String: String] = [:]

    /// Photos are downscaled to this before upload.
    nonisolated static let uploadMaxDimension: CGFloat = 1024

    func describe(constellation name: String) async throws -> String {
        if let cached = Self.cache[name] { return cached }

        let prompt = """
        You're the guide in a stargazing app. Tell a curious student about the \
        constellation \(name) in under 120 words, as short plain-text paragraphs \
        (no markdown): the myth or story behind it, its brightest or most famous \
        stars, when it's best seen from Canada, and one fun fact.
        """
        let text = try await generate(parts: [["text": prompt]]) ?? "No description available."
        Self.cache[name] = text
        return text
    }

    /// Checks whether a photo is a usable night-sky measurement. Gemini must answer with JSON
    /// matching `SkyAnalysis`, enforced by a response schema and validated again here.
    func analyzeSky(_ image: UIImage) async throws -> SkyAnalysis {
        let jpeg = try await Self.uploadJPEG(for: image)
        let parts: [[String: Any]] = [
            ["text": Self.skyPrompt],
            ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
        ]
        let config: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": Self.skySchema,
            "temperature": 0,
        ]
        guard let text = try await generate(parts: parts, generationConfig: config),
              let data = text.data(using: .utf8) else {
            throw GeminiError.badResponse
        }
        return try SkyAnalysis.validated(fromJSON: data)
    }

    /// Downscaling and JPEG encoding happen off the main thread.
    @concurrent
    private nonisolated static func uploadJPEG(for image: UIImage) async throws -> Data {
        guard let data = image.jpegData(maxDimension: uploadMaxDimension) else {
            throw GeminiError.unreadableImage
        }
        return data
    }

    /// Sends one request and returns the first candidate's text (nil if Gemini returned none).
    private func generate(parts: [[String: Any]], generationConfig: [String: Any]? = nil) async throws -> String? {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        var body: [String: Any] = ["contents": [["parts": parts]]]
        if let generationConfig {
            body["generationConfig"] = generationConfig
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw GeminiError.offline
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? GeminiError.rateLimited : GeminiError.server(status: http.statusCode)
        }

        // Dig out candidates[0].content.parts[0].text
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let textParts = content?["parts"] as? [[String: Any]]
        return textParts?.first?["text"] as? String
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
    ]

    private static let skyPrompt = """
    You are the data-quality checker for a citizen-science app that measures light pollution. \
    The photo was taken with a phone pointed at the sky, often at night and often noisy or dark. \
    Do not identify constellations. Judge only whether this is a usable measurement of the night sky.

    - isNightSky: true only if the photo shows the sky at night (not daytime, twilight with a bright \
    sky, indoors, or a photo of a screen).
    - cloudCover: "none", "partial" or "overcast" for the visible sky.
    - obstructions: anything blocking or washing out the sky: "trees", "buildings", "streetlight", \
    "moon_glare", "other". Use an empty list if there are none.
    - estimatedVisibleStars: how many individual stars you can make out (0 if none). Don't count \
    noise, planes or lights on the ground.
    - skyBrightness: 1 to 9 like the Bortle scale. 1 = pristine dark sky with many stars, \
    9 = bright inner-city sky with almost none.
    - confidence: "low", "medium" or "high".
    - reason: one short sentence explaining the judgement.
    """

    private static let skySchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "isNightSky": ["type": "BOOLEAN"],
            "cloudCover": ["type": "STRING", "enum": CloudCover.allCases.map(\.rawValue)],
            "obstructions": [
                "type": "ARRAY",
                "items": ["type": "STRING", "enum": Obstruction.allCases.map(\.rawValue)],
            ],
            "estimatedVisibleStars": ["type": "INTEGER", "minimum": 0],
            "skyBrightness": ["type": "INTEGER", "minimum": 1, "maximum": 9],
            "confidence": ["type": "STRING", "enum": SkyConfidence.allCases.map(\.rawValue)],
            "reason": ["type": "STRING"],
        ],
        "required": [
            "isNightSky", "cloudCover", "obstructions", "estimatedVisibleStars",
            "skyBrightness", "confidence", "reason",
        ],
        "propertyOrdering": [
            "isNightSky", "cloudCover", "obstructions", "estimatedVisibleStars",
            "skyBrightness", "confidence", "reason",
        ],
    ]
}
