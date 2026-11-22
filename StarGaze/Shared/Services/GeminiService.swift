import UIKit

/// Talks to the Gemini REST API. Its only job is `analyzeSky(_:)`, the quality check for sky
/// readings. It never identifies constellations; identification is sensor-based.
final class GeminiService {
    private let model = "gemini-3.5-flash-lite"

    /// Photos are downscaled to this before upload.
    nonisolated static let uploadMaxDimension: CGFloat = 1024

    /// Checks whether a photo is a usable night-sky measurement. Gemini must answer with JSON
    /// matching `SkyAnalysis`, enforced by a response schema and validated again here.
    /// `context` (live photos only) tells Gemini what the phone was aimed at.
    func analyzeSky(_ image: UIImage, context: SkyAnalysisContext? = nil,
                    timeout: TimeInterval = 60) async throws -> SkyAnalysis {
        let jpeg = try await Self.uploadJPEG(for: image)
        let contextText = context?.promptText
            ?? "No context: this photo came from the library. Set targetPatternVisible to false."
        let parts: [[String: Any]] = [
            ["text": Self.skyPrompt],
            ["text": contextText],
            ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
        ]
        let config: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": Self.skySchema,
            "temperature": 0,
        ]
        guard let text = try await generate(parts: parts, generationConfig: config, timeout: timeout),
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
    private func generate(parts: [[String: Any]], generationConfig: [String: Any],
                          timeout: TimeInterval) async throws -> String? {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = ["contents": [["parts": parts]], "generationConfig": generationConfig]
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
    The photo was taken with a phone held up to the night sky: a short handheld exposure, often dark, \
    grainy and orange from city light. Do not identify constellations from scratch. Your main job is to \
    say whether something other than light pollution explains how few stars are visible.

    A clear but bright city sky with few or no visible stars is a VALID light-pollution reading. \
    Only flag the photo if clouds, lights in frame, haze, blur, or a non-sky subject explain the missing stars. \
    Most photos come from cities, so a featureless orange or grey-blue clear sky is normal and fine.

    - isNightSky: false if the photo mostly shows the ground, a room, a ceiling, a screen, or daytime \
    or twilight sky, or if it is almost entirely black with no sky glow, gradient or stars at all \
    (lens covered). A dark but visibly sky-like frame is still a night sky.
    - cloudCover: "none", "partial" or "overcast" for the visible sky. Use "overcast" only when cloud \
    covers almost all of it (often a uniform lit cloud deck with visible texture). A smooth, even city \
    glow is not cloud.
    - obstructions: everything that applies, or an empty list:
      "trees", "buildings": blocking part of the sky.
      "streetlight": any streetlight, lamp, floodlight, window or other bright artificial light inside the frame.
      "moon_glare": the Moon in the frame or its glare washing out part of the sky.
      "haze": fog, haze or smoke.
      "blur": heavy motion blur or out of focus (stars smeared into lines or blobs).
      "lens": smudged or fogged lens, or a finger or object partly covering it.
      "other": anything else blocking the sky.
    - estimatedVisibleStars: how many individual stars you can make out (0 if none). Don't count \
    noise, grain, planes, satellites or lights on the ground.
    - skyBrightness: 1 to 9 like the Bortle scale. 1 = pristine dark sky with many stars, \
    9 = bright inner-city sky with almost none. This is only a rough second opinion.
    - confidence: "low", "medium" or "high" about this quality judgement.
    - targetPatternVisible: true only if the stick-figure pattern of the named target constellation \
    (its brightest stars in their recognisable arrangement) can actually be seen in the photo. \
    False if only a few unrelated stars are visible, or if there is no target.
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
            "targetPatternVisible": ["type": "BOOLEAN"],
            "reason": ["type": "STRING"],
        ],
        "required": [
            "isNightSky", "cloudCover", "obstructions", "estimatedVisibleStars",
            "skyBrightness", "confidence", "targetPatternVisible", "reason",
        ],
        "propertyOrdering": [
            "isNightSky", "cloudCover", "obstructions", "estimatedVisibleStars",
            "skyBrightness", "confidence", "targetPatternVisible", "reason",
        ],
    ]
}
