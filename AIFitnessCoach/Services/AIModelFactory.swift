import Foundation
import GoogleGenerativeAI

// MARK: - Epic #53: Multi-provider client-factory
//
// Dit bestand bevat het provider-client-subsysteem: één `AIModelFactory` die op
// basis van de gekozen `AIProvider` een `GenerativeModelProtocol`-conforme client
// teruggeeft, plus de concrete clients (Gemini via de officiële SDK, OpenAI/Mistral
// via één OpenAI-compatibele REST-client, en Anthropic via de Messages-API).
//
// De types leven samen omdat ze één verantwoordelijkheid delen (een prompt naar
// een provider sturen en de tekst teruggeven). Per-provider verschillen — system-
// instructie-plaatsing, JSON-mode en fout-mapping — worden hier ingekapseld zodat
// de call-sites (`ChatViewModel`, `WorkoutInsightService`, `AddGoalView`) volledig
// provider-agnostisch blijven.

enum AIModelFactory {

    /// Bouwt een provider-client voor één coach-/insight-call.
    ///
    /// - Parameters:
    ///   - provider: de door de gebruiker gekozen AI-provider.
    ///   - modelName: de modelnaam zoals die voor de provider geldt.
    ///   - systemInstruction: de system-prompt; leeg ⇒ geen system-instructie.
    ///   - jsonMode: of het model JSON-output moet forceren (chat-coach = true,
    ///     vrije-tekst-insight/TRIMP-schatting = false).
    ///   - timeout: request-timeout in seconden.
    ///   - apiKey: de BYOK-sleutel van de gebruiker voor deze provider.
    ///   - session: injecteerbaar voor unit-tests (REST-clients); Gemini negeert dit.
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

// MARK: - Gemini-adapter

/// Wrapper rondom de officiële `GoogleGenerativeAI.GenerativeModel` die het
/// SDK-onafhankelijke `GenerativeModelProtocol` implementeert door de neutrale
/// `AIPromptPart`-array naar `ModelContent.Part` te mappen.
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

// MARK: - OpenAI-compatibele REST-client (OpenAI + Mistral)

/// Bedient zowel OpenAI als Mistral — beide spreken het `/v1/chat/completions`-
/// formaat met `Authorization: Bearer`-auth en `response_format` voor JSON-mode.
struct OpenAICompatibleModelClient: GenerativeModelProtocol, RealAIProviderClient {

    /// De smaak bepaalt endpoint + (later) provider-specifieke nuances.
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

    /// OpenAI/Mistral accepteren een platte string als er geen afbeelding is, en
    /// anders een content-array met tekst- en `image_url`-blokken (base64 data-URL).
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

// MARK: - Anthropic Messages-API-client

/// Anthropic spreekt `/v1/messages` met `x-api-key`-auth en heeft geen native
/// JSON-mode. JSON wordt geforceerd via assistant-prefill (`{`): we sturen een
/// half-afgemaakte assistant-turn en plakken de `{` weer voor de respons.
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
            // Prefill dwingt het model om met een JSON-object te beginnen.
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
        // De prefill-`{` zit niet in de respons — plak hem er weer voor zodat de
        // JSON-parser aan de call-site een volledig object ziet.
        return jsonMode ? "{" + responseText : responseText
    }
}

// MARK: - Gedeelde helpers

/// Splitst een `AIPromptPart`-array in samengevoegde tekst + losse afbeeldingen.
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

/// Vertaalt een HTTP-respons naar een `AIProviderError` (of laat 2xx door).
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
            // Neem de (ingekorte) foutbody mee zodat de gebruiker de échte reden
            // ziet — bv. "model: ... not found" bij een gedeprecieerd model.
            throw AIProviderError.http(status: http.statusCode, message: shortBody(data))
        }
    }

    /// Eerste ~300 tekens van de respons-body als platte tekst (zonder newlines),
    /// genoeg om een provider-foutmelding te herkennen zonder de UI te overspoelen.
    private static func shortBody(_ data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let collapsed = raw.replacingOccurrences(of: "\n", with: " ")
        return collapsed.count > 300 ? String(collapsed.prefix(300)) + "…" : collapsed
    }
}

// MARK: - Epic #54: Dynamische model-catalogus per provider

/// Haalt de live model-lijst op bij OpenAI/Anthropic/Mistral, **direct vanaf het
/// toestel met de BYOK-sleutel van de gebruiker** (de sleutel verlaat het toestel
/// niet via onze servers — net als de chat-calls). Zo ziet de gebruiker exact de
/// modellen die zijn key mag aanroepen, inclusief net-uitgebrachte versies.
///
/// Gemini loopt bewust níét via deze service maar via de Cloudflare Worker
/// (`AIModelCatalogService`) met onze eigen key — een globale, gevalideerde lijst.
/// De caller valt bij een fout of lege sleutel terug op `AIModelCatalog.builtIn(for:)`.
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
            // Nieuwere versies bovenaan (heuristisch via aflopende id-sortering).
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

    /// Filtert de (vaak ruisende) provider-lijst naar chat-bruikbare tekstmodellen.
    static func isChatModel(provider: AIProvider, item: ModelListResponse.Item) -> Bool {
        switch provider {
        case .anthropic:
            // Anthropic's lijst bevat uitsluitend chat-modellen (claude-*).
            return true
        case .mistral:
            // Mistral markeert chat-support expliciet; sluit embeddings/OCR uit.
            if let chat = item.capabilities?.completion_chat { return chat }
            return !item.id.lowercased().contains("embed")
        case .openAI:
            // OpenAI's lijst bevat ook embeddings/audio/image/whisper/etc. zonder
            // duidelijke chat-markering → heuristisch filteren op id.
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

/// Uniforme decode van de `/v1/models`-responses (OpenAI/Anthropic/Mistral delen
/// het `{ "data": [ { "id": ... } ] }`-grondvorm; velden die een provider niet
/// levert blijven nil).
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

// MARK: - Respons-DTO's

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
