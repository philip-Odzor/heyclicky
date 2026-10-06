import Foundation

/// Everything the model needs to turn a spoken instruction into finished text.
struct WriteRequest {
    let instruction: String
    let app: FrontmostApp
    let screenshotJPEG: Data?
    let skills: [Skill]
    /// Local-only recalled memories (MemoryStore). Empty = none.
    var memories: [String] = []
}

protocol LLMProviding {
    func write(_ request: WriteRequest) async throws -> String
    /// Streams the reply, calling onSentence for each finished sentence so
    /// voice can overlap generation. Default: one call with the full text.
    func writeStreaming(
        _ request: WriteRequest,
        onSentence: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

extension LLMProviding {
    func writeStreaming(
        _ request: WriteRequest,
        onSentence: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let full = try await write(request)
        for sentence in SpeechResponder.sentences(from: full) {
            onSentence(sentence)
        }
        return full
    }
}

/// Calls any OpenAI-compatible Chat Completions API with the screenshot
/// attached so the model can produce text that fits what's on screen.
/// Works with OpenAI, OpenRouter, Groq, Gemini (OpenAI-compat), Ollama,
/// and a local Hermes API server — same JSON shape, different baseURL.
struct OpenAIClient: LLMProviding {
    let apiKey: String
    let model: String
    var baseURL: URL = URL(string: "https://api.openai.com/v1/chat/completions")!

    private var endpoint: URL { baseURL }

    func write(_ request: WriteRequest) async throws -> String {
        guard !model.isEmpty else { throw LLMError.missingKey }
        if providerNeedsKey && apiKey.isEmpty { throw LLMError.missingKey }

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
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // OpenRouter needs these; harmless everywhere else.
        urlRequest.setValue("heyclicky/1.0", forHTTPHeaderField: "X-Title")
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

    func writeStreaming(
        _ request: WriteRequest,
        onSentence: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard !model.isEmpty else { throw LLMError.missingKey }
        if providerNeedsKey && apiKey.isEmpty { throw LLMError.missingKey }

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
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt(for: request)],
                ["role": "user", "content": content]
            ]
        ]

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("heyclicky/1.0", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw LLMError.badResponse
        }

        var full = ""
        var pending = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta.content,
                  !delta.isEmpty else { continue }
            full += delta
            pending += delta
            // Emit finished sentences as they arrive; hold back the tail
            // unless it already ends with a terminator.
            let endsTerminated = pending.last.map { ".!?\n".contains($0) } ?? false
            var sentences = SpeechResponder.sentences(from: pending)
            guard !sentences.isEmpty else { continue }
            let holdBack = endsTerminated ? [] : [sentences.removeLast()]
            for s in sentences {
                onSentence(s)
            }
            pending = holdBack.first ?? ""
        }
        // Flush remainder.
        for sentence in SpeechResponder.sentences(from: pending) {
            onSentence(sentence)
        }
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
    }

    /// Local endpoints (Ollama / Hermes proxy) allow empty keys.
    private var providerNeedsKey: Bool {
        let host = endpoint.host?.lowercased() ?? ""
        return !(host == "localhost" || host == "127.0.0.1")
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
        if !request.memories.isEmpty {
            prompt += "\n\nLocal memory (user's own past turns, local-only — prefer it over guessing):\n"
            for m in request.memories.prefix(8) {
                prompt += "\n- \(m)\n"
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

    private struct ChatStreamChunk: Decodable {
        struct Choice: Decodable { let delta: Delta }
        struct Delta: Decodable { let content: String? }
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
        case .missingKey: return "Add a model API key in Settings (or use Ollama / Hermes local, no key) to use screen-aware writing."
        case .badResponse: return "Unexpected response from the model."
        case .emptyResponse: return "The model returned nothing."
        case .server(let status, _): return "The model request failed (HTTP \(status))."
        }
    }
}
