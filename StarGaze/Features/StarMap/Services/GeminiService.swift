import Foundation

/// Asks Gemini to describe a constellation. Answers are cached so each
/// constellation only costs one request (free tier: 500 requests/day).
final class GeminiService {
    private let model = "gemini-3.5-flash-lite"
    private static var cache: [String: String] = [:]

    func describe(constellation name: String) async throws -> String {
        if let cached = Self.cache[name] { return cached }

        let prompt = """
        You're the guide in a stargazing app. Tell a curious student about the \
        constellation \(name) in under 120 words, as short plain-text paragraphs \
        (no markdown): the myth or story behind it, its brightest or most famous \
        stars, when it's best seen from Canada, and one fun fact.
        """
        let text = try await generateText(prompt: prompt)
        Self.cache[name] = text
        return text
    }

    private func generateText(prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
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
        return parts?.first?["text"] as? String ?? "No description available."
    }
}
