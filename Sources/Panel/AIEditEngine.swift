import Foundation
import FoundationModels

/// Text-in, text-out edit engine. Providers differ only in how they produce the
/// string; the interaction (panel, cancellation, error surface) is backend-agnostic.
protocol AIEditEngine: Sendable {
    func edit(instructions: String, text: String) async throws -> String
}

enum AIEditError: LocalizedError {
    case modelUnavailable(String)
    case invalidEndpoint(String)
    case network(String)
    case httpStatus(Int, String)
    case emptyResponse
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let message): message
        case .invalidEndpoint(let detail): "AI Editing endpoint is not configured: \(detail)"
        case .network(let detail): "AI Editing endpoint is unreachable: \(detail)"
        case .httpStatus(let status, let body): "AI Editing endpoint returned HTTP \(status): \(body)"
        case .emptyResponse: "The AI Editing provider returned an empty result."
        case .malformedResponse(let detail): "AI Editing endpoint response was malformed: \(detail)"
        }
    }
}

/// Apple's zero-download model with structured output.
struct AppleEditEngine: AIEditEngine {
    @Generable(description: "Text ready to replace the user's selected text")
    struct Output {
        @Guide(description: "Replacement text only; no label, explanation, quotation marks, or markdown fence")
        var text: String
    }

    func edit(instructions: String, text: String) async throws -> String {
        let model = SystemLanguageModel(useCase: .general,
                                        guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw AIEditError.modelUnavailable(Self.unavailabilityMessage(model.availability))
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: "Transform the following selected text:\n\n\(text)",
            generating: Output.self
        )
        guard !response.content.text.isEmpty else { throw AIEditError.emptyResponse }
        return response.content.text
    }

    private static func unavailabilityMessage(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: "The on-device language model is available."
        case .unavailable(.deviceNotEligible): "This Mac cannot run the Apple on-device language model."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings, then try again."
        case .unavailable(.modelNotReady): "The on-device language model is still downloading. Try again later."
        @unknown default: "The on-device language model is unavailable."
        }
    }
}

/// Talks to any OpenAI-compatible `/v1/chat/completions` server: mlx_lm.server,
/// LM Studio, Ollama, llama.cpp — including a resident server on another machine.
struct OpenAICompatibleEditEngine: AIEditEngine {
    let settings: AIEditSettings

    struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        enum CodingKeys: String, CodingKey {
            case messages, temperature, stream
            case maxTokens = "max_tokens"
        }

        let messages: [Message]
        let temperature = 0.0
        let stream = false
        let maxTokens = 512

        init(messages: [Message]) {
            self.messages = messages
        }

        /// The model field is omitted entirely: several OpenAI-compatible servers
        /// (mlx_lm.server among them) treat it as "load this model" rather than
        /// "route to this deployment", so any value we sent could start a bogus
        /// remote fetch. Which model serves the endpoint is the operator's business.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(messages, forKey: .messages)
            try container.encode(temperature, forKey: .temperature)
            try container.encode(stream, forKey: .stream)
            try container.encode(maxTokens, forKey: .maxTokens)
        }
    }

    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    func edit(instructions: String, text: String) async throws -> String {
        try await withTimeoutOrThrow {
            try await requestOnce(instructions: instructions, text: text)
        }
    }

    private func requestOnce(instructions: String, text: String) async throws -> String {
        guard settings.isEndpointConfigured, let url = URL(string: settings.endpointURL) else {
            throw AIEditError.invalidEndpoint("set an http(s) chat-completions URL in AI Editing settings")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(
            messages: [.init(role: "system", content: instructions),
                       .init(role: "user", content: text)]
        ))

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw AIEditError.network(error.localizedDescription)
        } catch {
            throw AIEditError.network(error.localizedDescription)
        }
        guard let http = urlResponse as? HTTPURLResponse else {
            throw AIEditError.network("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIEditError.httpStatus(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }

        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIEditError.malformedResponse(error.localizedDescription)
        }
        let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw AIEditError.emptyResponse }
        return content
    }

    /// URLRequest's timeoutInterval only bounds idle socket time; a wall-clock cap
    /// bounds the whole call so the panel can never park past the user's patience.
    private func withTimeoutOrThrow(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(self.settings.timeout))
                throw AIEditError.network("timed out after \(Int(self.settings.timeout)) s")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

/// Builds the engine for the provider selected in AI Editing settings.
enum AIEditEngineFactory {
    static func active(settings: AIEditSettings) -> any AIEditEngine {
        switch settings.provider {
        case .appleOnDevice: return AppleEditEngine()
        case .openAICompatible: return OpenAICompatibleEditEngine(settings: settings)
        }
    }
}
