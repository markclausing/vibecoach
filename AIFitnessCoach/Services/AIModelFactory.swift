import Foundation
import GoogleGenerativeAI

// MARK: - Epic #53: Multi-provider client factory
//
// This file contains the provider-client subsystem: one `AIModelFactory` that,
// based on the chosen `AIProvider`, returns a `GenerativeModelProtocol`-conforming client,
// plus the concrete clients (Gemini via the official SDK, OpenAI/Mistral
// via one OpenAI-compatible REST client, and Anthropic via the Messages API).
//
// The types live together because they share one responsibility (send a prompt to
// a provider and return the text). Per-provider differences — system-instruction
// placement, JSON mode and error mapping — are encapsulated here so
// the call sites (`ChatViewModel`, `WorkoutInsightService`, `AddGoalView`) stay fully
// provider-agnostic.

enum AIModelFactory {

    /// Builds a provider client for one coach/insight call.
    ///
    /// - Parameters:
    ///   - provider: the AI provider chosen by the user.
    ///   - modelName: the model name as it applies for the provider.
    ///   - systemInstruction: the system prompt; empty ⇒ no system instruction.
    ///   - jsonMode: whether the model must force JSON output (chat coach = true,
    ///     free-text insight/TRIMP estimation = false).
    ///   - timeout: request timeout in seconds.
    ///   - apiKey: the user's BYOK key for this provider.
    ///   - session: injectable for unit tests (REST clients); Gemini ignores this.
    static func makeModel(
        provider: AIProvider,
        modelName: String,
        systemInstruction: String,
        jsonMode: Bool,
        timeout: TimeInterval,
        apiKey: String,
        session: URLSession = .shared
    ) -> GenerativeModelProtocol {
        switch provider {
        case .gemini:
            return makeGeminiModel(
                modelName: modelName,
                systemInstruction: systemInstruction,
                jsonMode: jsonMode,
                timeout: timeout,
                apiKey: apiKey
            )
        case .openAI:
            return OpenAICompatibleModelClient(
                flavor: .openAI,
                modelName: modelName,
                systemInstruction: systemInstruction,
                jsonMode: jsonMode,
                timeout: timeout,
                apiKey: apiKey,
                session: session
            )
        case .mistral:
            return OpenAICompatibleModelClient(
                flavor: .mistral,
                modelName: modelName,
                systemInstruction: systemInstruction,
                jsonMode: jsonMode,
                timeout: timeout,
                apiKey: apiKey,
                session: session
            )
        case .anthropic:
            return AnthropicModelClient(
                modelName: modelName,
                systemInstruction: systemInstruction,
                jsonMode: jsonMode,
                timeout: timeout,
                apiKey: apiKey,
                session: session
            )
        }
    }

    private static func makeGeminiModel(
        modelName: String,
        systemInstruction: String,
        jsonMode: Bool,
        timeout: TimeInterval,
        apiKey: String
    ) -> GenerativeModelProtocol {
        let config = jsonMode
            ? GenerationConfig(responseMIMEType: "application/json")
            : GenerationConfig()
        let options = RequestOptions(timeout: timeout)
        let systemContent = systemInstruction.isEmpty
            ? nil
            : ModelContent(role: "system", parts: [.text(systemInstruction)])
        let googleModel = GenerativeModel(
            name: modelName,
            apiKey: apiKey,
            generationConfig: config,
            systemInstruction: systemContent,
            requestOptions: options
        )
        return RealGenerativeModel(model: googleModel)
    }
}

// MARK: - Gemini adapter

/// Wrapper around the official `GoogleGenerativeAI.GenerativeModel` that implements
/// the SDK-independent `GenerativeModelProtocol` by mapping the neutral
/// `AIPromptPart` array to `ModelContent.Part`.
public struct RealGenerativeModel: GenerativeModelProtocol, RealAIProviderClient {
    private let model: GenerativeModel

    public init(model: GenerativeModel) {
        self.model = model
    }

    public func generateContent(_ parts: [AIPromptPart]) async throws -> String? {
        let sdkParts: [ModelContent.Part] = parts.map { part in
            switch part {
            case .text(let text):
                return .text(text)
            case .imageData(let data, let mimeType):
                return .data(mimetype: mimeType, data)
            }
        }
        let modelContent = ModelContent(role: "user", parts: sdkParts)
        let response = try await model.generateContent([modelContent])
        return response.text
    }
}

// MARK: - OpenAI-compatible REST client (OpenAI + Mistral)

/// Serves both OpenAI and Mistral — both speak the `/v1/chat/completions`
/// format with `Authorization: Bearer` auth and `response_format` for JSON mode.
struct OpenAICompatibleModelClient: GenerativeModelProtocol, RealAIProviderClient {

    /// The flavor determines the endpoint + (later) provider-specific nuances.
    enum Flavor {
        case openAI
        case mistral

        var endpoint: URL {
            switch self {
            case .openAI:  return URL(string: "https://api.openai.com/v1/chat/completions")!
            case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")!
            }
        }
    }

    let flavor: Flavor
    let modelName: String
    let systemInstruction: String
    let jsonMode: Bool
    let timeout: TimeInterval
    let apiKey: String
    var session: URLSession = .shared

    func generateContent(_ parts: [AIPromptPart]) async throws -> String? {
        let (text, images) = AIPromptPartSplitter.split(parts)

        var messages: [[String: Any]] = []
        if !systemInstruction.isEmpty {
            messages.append(["role": "system", "content": systemInstruction])
        }
        messages.append(["role": "user", "content": Self.userContent(text: text, images: images)])

        var body: [String: Any] = [
            "model": modelName,
            "messages": messages
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        var request = URLRequest(url: flavor.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        try AIProviderHTTP.validate(response, data: data)

        guard let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data) else {
            throw AIProviderError.decodingFailed
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIProviderError.emptyResponse
        }
        return content
    }

    /// OpenAI/Mistral accept a plain string when there is no image, and
    /// otherwise a content array with text and `image_url` blocks (base64 data URL).
    private static func userContent(text: String, images: [(data: Data, mimeType: String)]) -> Any {
        guard !images.isEmpty else { return text }
        var blocks: [[String: Any]] = []
        if !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        for image in images {
            let dataURL = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
            blocks.append(["type": "image_url", "image_url": ["url": dataURL]])
        }
        return blocks
    }
}

// MARK: - Anthropic Messages-API client

/// Anthropic speaks `/v1/messages` with `x-api-key` auth and has no native
/// JSON mode. JSON is forced via an assistant prefill (`{`): we send a
/// half-finished assistant turn and paste the `{` back in front of the response.
struct AnthropicModelClient: GenerativeModelProtocol, RealAIProviderClient {

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"
    static let maxTokens = 4096

    let modelName: String
    let systemInstruction: String
    let jsonMode: Bool
    let timeout: TimeInterval
    let apiKey: String
    var session: URLSession = .shared

    func generateContent(_ parts: [AIPromptPart]) async throws -> String? {
        let (text, images) = AIPromptPartSplitter.split(parts)

        var content: [[String: Any]] = []
        if !text.isEmpty {
            content.append(["type": "text", "text": text])
        }
        for image in images {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ])
        }

        var messages: [[String: Any]] = [["role": "user", "content": content]]
        if jsonMode {
            // The prefill forces the model to start with a JSON object.
            messages.append(["role": "assistant", "content": "{"])
        }

        var body: [String: Any] = [
            "model": modelName,
            "max_tokens": Self.maxTokens,
            "messages": messages
        ]
        if !systemInstruction.isEmpty {
            body["system"] = systemInstruction
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        try AIProviderHTTP.validate(response, data: data)

        guard let decoded = try? JSONDecoder().decode(AnthropicMessageResponse.self, from: data) else {
            throw AIProviderError.decodingFailed
        }
        let responseText = decoded.content.compactMap { $0.text }.joined()
        guard !responseText.isEmpty else { throw AIProviderError.emptyResponse }
        // The prefill `{` is not in the response — paste it back in front so the
        // JSON parser at the call site sees a complete object.
        return jsonMode ? "{" + responseText : responseText
    }
}

// MARK: - Shared helpers

/// Splits an `AIPromptPart` array into combined text + separate images.
enum AIPromptPartSplitter {
    static func split(_ parts: [AIPromptPart]) -> (text: String, images: [(data: Data, mimeType: String)]) {
        var textPieces: [String] = []
        var images: [(data: Data, mimeType: String)] = []
        for part in parts {
            switch part {
            case .text(let text):
                textPieces.append(text)
            case .imageData(let data, let mimeType):
                images.append((data, mimeType))
            }
        }
        return (textPieces.joined(separator: "\n"), images)
    }
}

/// Translates an HTTP response into an `AIProviderError` (or lets 2xx through).
enum AIProviderHTTP {
    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 429, 503, 529:
            throw AIProviderError.overloaded
        case 401, 403:
            throw AIProviderError.authenticationFailed
        default:
            // Include the (truncated) error body so the user sees the real reason
            // — e.g. "model: ... not found" for a deprecated model.
            throw AIProviderError.http(status: http.statusCode, message: shortBody(data))
        }
    }

    /// First ~300 characters of the response body as plain text (without newlines),
    /// enough to recognise a provider error message without flooding the UI.
    private static func shortBody(_ data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let collapsed = raw.replacingOccurrences(of: "\n", with: " ")
        return collapsed.count > 300 ? String(collapsed.prefix(300)) + "…" : collapsed
    }
}

// MARK: - Epic #54: Dynamic model catalog per provider

/// Fetches the live model list from OpenAI/Anthropic/Mistral, **directly from the
/// device with the user's BYOK key** (the key does not leave the device via our
/// servers — just like the chat calls). This way the user sees exactly the
/// models their key may call, including just-released versions.
///
/// Gemini deliberately does NOT go via this service but via the Cloudflare Worker
/// (`AIModelCatalogService`) with our own key — a global, validated list.
/// On an error or empty key the caller falls back to `AIModelCatalog.builtIn(for:)`.
struct ProviderModelListService {
    var session: URLSession = .shared

    func fetchModels(provider: AIProvider, apiKey: String) async throws -> [AIModelDescriptor] {
        guard provider != .gemini else {
            return AIModelCatalog.builtIn(for: .gemini).models
        }

        var request = URLRequest(url: Self.endpoint(for: provider))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch provider {
        case .openAI, .mistral:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicModelClient.apiVersion, forHTTPHeaderField: "anthropic-version")
        case .gemini:
            break
        }

        let (data, response) = try await session.data(for: request)
        try AIProviderHTTP.validate(response, data: data)

        guard let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
            throw AIProviderError.decodingFailed
        }

        let descriptors = decoded.data
            .filter { Self.isChatModel(provider: provider, item: $0) }
            .map { AIModelDescriptor(id: $0.id, displayName: $0.display_name ?? $0.name ?? $0.id) }
            // Newer versions on top (heuristically via descending id sorting).
            .sorted { $0.id > $1.id }

        guard !descriptors.isEmpty else { throw AIProviderError.emptyResponse }
        return descriptors
    }

    static func endpoint(for provider: AIProvider) -> URL {
        switch provider {
        case .openAI:    return URL(string: "https://api.openai.com/v1/models")!
        case .mistral:   return URL(string: "https://api.mistral.ai/v1/models")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        }
    }

    /// Filters the (often noisy) provider list down to chat-capable text models.
    static func isChatModel(provider: AIProvider, item: ModelListResponse.Item) -> Bool {
        switch provider {
        case .anthropic:
            // Anthropic's list contains only chat models (claude-*).
            return true
        case .mistral:
            // Mistral marks chat support explicitly; excludes embeddings/OCR.
            if let chat = item.capabilities?.completion_chat { return chat }
            return !item.id.lowercased().contains("embed")
        case .openAI:
            // OpenAI's list also contains embeddings/audio/image/whisper/etc. without
            // a clear chat marker → filter heuristically on id.
            let id = item.id.lowercased()
            let chatFamily = ["gpt-", "chatgpt-", "o1", "o3", "o4"]
            guard chatFamily.contains(where: { id.hasPrefix($0) }) else { return false }
            let nonChat = ["embedding", "audio", "realtime", "transcribe", "tts",
                           "image", "whisper", "moderation", "dall-e", "search", "instruct"]
            return !nonChat.contains(where: { id.contains($0) })
        case .gemini:
            return true
        }
    }
}

/// Uniform decode of the `/v1/models` responses (OpenAI/Anthropic/Mistral share
/// the `{ "data": [ { "id": ... } ] }` base shape; fields a provider doesn't
/// supply stay nil).
struct ModelListResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let display_name: String?
        let name: String?
        let capabilities: Capabilities?
    }
    struct Capabilities: Decodable {
        let completion_chat: Bool?
    }
    let data: [Item]
}

// MARK: - Response DTOs

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable { let message: OpenAIChatMessage }
    let choices: [Choice]
}

private struct OpenAIChatMessage: Decodable {
    let content: String?
}

private struct AnthropicMessageResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}
