import Foundation

/// Everything the model needs to turn a spoken instruction into finished text.
struct WriteRequest {
    let instruction: String
    let app: FrontmostApp
    let screenshotJPEG: Data?
    let skills: [Skill]
}

protocol LLMProviding {
    func write(_ request: WriteRequest) async throws -> String
}

/// Calls OpenAI's Chat Completions API with the screenshot attached so the
/// model can produce text that fits what's on screen.
struct OpenAIClient: LLMProviding {
    let apiKey: String
    let model: String

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func write(_ request: WriteRequest) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingKey }

        var content: [[String: Any]] = [
            ["type": "text", "text": userPrompt(for: request)]
        ]
        if let jpeg = request.screenshotJPEG {
            let base64 = jpeg.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": systemPrompt(for: request)],
                ["role": "user", "content": content]
            ]
        ]

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.server(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func systemPrompt(for request: WriteRequest) -> String {
        var prompt = """
        You are clicky, a screen-aware dictation assistant that lives on the \
        user's Mac. The user speaks an instruction out loud while looking at \
        their screen; you produce the exact text that should be inserted where \
        their cursor is.

        Rules:
        - Output ONLY the text to insert. No preamble, no quotes, no markdown \
        fences, no commentary.
        - Match the tone and format of the app the user is in.
        - Use the screenshot as context for what they're referring to.
        - Write in the user's first-person voice when replying to messages.

        The user is currently in: \(request.app.name).
        """

        if !request.skills.isEmpty {
            prompt += "\n\nRelevant skills the user has enabled:\n"
            for skill in request.skills {
                prompt += "\n## \(skill.name)\n\(skill.body)\n"
            }
        }
        return prompt
    }

    private func userPrompt(for request: WriteRequest) -> String {
        let instruction = request.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Spoken instruction: \"\(instruction)\"\n\nWrite the text to insert."
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }
}

/// Used for previews and when no API key is configured, so the flow is still
/// demoable without a network call.
struct EchoLLM: LLMProviding {
    func write(_ request: WriteRequest) async throws -> String {
        let ctx = request.app.name
        return "[clicky demo — no API key set]\nIn \(ctx), you asked: \"\(request.instruction)\""
    }
}

enum LLMError: LocalizedError {
    case missingKey
    case badResponse
    case emptyResponse
    case server(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your OpenAI API key in Settings to use screen-aware writing."
        case .badResponse: return "Unexpected response from the model."
        case .emptyResponse: return "The model returned nothing."
        case .server(let status, _): return "The model request failed (HTTP \(status))."
        }
    }
}
