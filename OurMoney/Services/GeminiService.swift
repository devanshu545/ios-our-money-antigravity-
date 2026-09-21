import Foundation

/// Gemini API client for iOS (equivalent of the Android `GenerativeModel` usage).
/// Uses the REST endpoint so no extra SDK is required. The API key is read from
/// Info.plist (`GEMINI_API_KEY`), mirroring Android's BuildConfig injection — never hardcoded.
struct GeminiService {
    /// Must match the model used on Android (`AiViewModel.kt`).
    static let modelName = "gemini-3.5-flash"

    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? ""
    }

    struct GenerateResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    /// Sends a single prompt (full conversation flattened, same approach as Android) and
    /// returns the model's text. Throws with a readable message on failure.
    func generateContent(prompt: String, systemInstruction: String) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError.missingKey
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.modelName):generateContent?key=\(key)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        struct Payload: Encodable {
            struct Content: Encodable {
                let parts: [Part]
                init(text: String) { parts = [Part(text: text)] }
            }
            struct Part: Encodable {
                let text: String
            }
            let contents: [Content]
            let systemInstruction: Content
        }

        let payload = Payload(
            contents: [Payload.Content(text: prompt)],
            systemInstruction: Payload.Content(text: systemInstruction)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http(status: http.statusCode, body: bodyText)
        }
        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        guard let text = decoded.candidates?.first?.content?.parts?
            .compactMap(\.text).joined(separator: "\n"), !text.isEmpty else {
            return "No response generated."
        }
        return text
    }

    enum GeminiError: LocalizedError {
        case missingKey
        case http(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Gemini API Key is missing. Please add it to Secrets."
            case .http(let status, let body):
                return "Gemini request failed (\(status)). \(body.prefix(200))"
            }
        }
    }
}
