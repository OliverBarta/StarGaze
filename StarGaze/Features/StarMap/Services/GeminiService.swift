import Foundation
import UIKit

/// Sends a star photo to Gemini and gets back the constellations it sees.
final class GeminiService {
    private let model = "gemini-3.5-flash-lite"

    /// Returns Gemini's JSON answer as a String (decoded into GeminiResult by the view).
    func identifyConstellations(in image: UIImage) async throws -> String {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let prompt = """
        Identify the constellations visible in this night-sky photo.
        Reply with JSON only, in this shape:
        {"constellations":[{"name":"Orion",
          "stars":[{"name":"Betelgeuse","x":0.42,"y":0.31}],
          "lines":[[0,1]],
          "fact":"one short fun fact"}]}
        x and y are positions from 0 to 1 across the image width and height.
        "lines" lists pairs of star indexes to connect.
        If you see no constellations, return {"constellations":[]}.
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg",
                                     "data": jpeg.base64EncodedString()]]
                ]
            ]],
            "generationConfig": ["response_mime_type": "application/json"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Gemini", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }

        // Dig out candidates[0].content.parts[0].text
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        return parts?.first?["text"] as? String ?? "{\"constellations\":[]}"
    }
}
