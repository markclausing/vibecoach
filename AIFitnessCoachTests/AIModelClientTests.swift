import XCTest
@testable import AIFitnessCoach

/// Epic #53 — unit-tests voor de provider-agnostische client-laag (OpenAI/Mistral/
/// Anthropic REST-clients + `AIModelFactory` + `AIProviderError`-classificatie).
///
/// Alle HTTP-verkeer loopt via `MockURLProtocol` — er gaat geen enkele live API-call
/// uit. We asserten op request-body-vorm (model, system-plaatsing, JSON-mode),
/// headers (auth) en de fout-mapping per statuscode.
final class AIModelClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func ok(_ request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    private func status(_ request: URLRequest, _ code: Int) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (response, Data("{}".utf8))
    }

    /// URLSession levert de body via een stream binnen URLProtocol — `httpBody` is
    /// daar nil. Deze helper leest beide gevallen uit.
    private func bodyJSON(_ request: URLRequest) -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 { collected.append(buffer, count: read) } else { break }
            }
            data = collected
        } else {
            return [:]
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - OpenAI / Mistral

    func testOpenAI_Success_ParsesContent_SendsBearerAuth_AndJSONMode() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            return self.ok(request, json: #"{"choices":[{"message":{"content":"{\"plan\":1}"}}]}"#)
        }
        let client = OpenAICompatibleModelClient(
            flavor: .openAI, modelName: "gpt-4o-mini", systemInstruction: "Jij bent een coach.",
            jsonMode: true, timeout: 10, apiKey: "sk-test", session: session
        )

        let result = try await client.generateContent([.text("hallo")])

        XCTAssertEqual(result, #"{"plan":1}"#)
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = bodyJSON(captured!)
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(messages?.first?["content"] as? String, "Jij bent een coach.")
        XCTAssertEqual(messages?.last?["role"] as? String, "user")
        XCTAssertEqual(messages?.last?["content"] as? String, "hallo")
    }

    func testOpenAI_NoJSONMode_OmitsResponseFormat() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            return self.ok(request, json: #"{"choices":[{"message":{"content":"4500"}}]}"#)
        }
        let client = OpenAICompatibleModelClient(
            flavor: .openAI, modelName: "gpt-4o-mini", systemInstruction: "",
            jsonMode: false, timeout: 10, apiKey: "sk-test", session: session
        )

        let result = try await client.generateContent([.text("hoeveel TRIMP?")])

        XCTAssertEqual(result, "4500")
        let body = bodyJSON(captured!)
        XCTAssertNil(body["response_format"], "JSON-mode uit ⇒ geen response_format")
        // Lege system-instructie ⇒ geen system-message.
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
    }

    func testOpenAI_ImagePart_BuildsContentArrayWithImageURL() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            return self.ok(request, json: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        }
        let client = OpenAICompatibleModelClient(
            flavor: .openAI, modelName: "gpt-4o", systemInstruction: "",
            jsonMode: false, timeout: 10, apiKey: "sk-test", session: session
        )

        _ = try await client.generateContent([.text("wat zie je?"), .imageData(Data([0x1, 0x2, 0x3]), mimeType: "image/jpeg")])

        let body = bodyJSON(captured!)
        let messages = body["messages"] as? [[String: Any]]
        let content = messages?.last?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.last?["type"] as? String, "image_url")
        let url = (content?.last?["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url?.hasPrefix("data:image/jpeg;base64,"), true)
    }

    func testMistral_UsesMistralEndpoint() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            return self.ok(request, json: #"{"choices":[{"message":{"content":"hoi"}}]}"#)
        }
        let client = OpenAICompatibleModelClient(
            flavor: .mistral, modelName: "mistral-small-latest", systemInstruction: "",
            jsonMode: false, timeout: 10, apiKey: "key", session: session
        )

        let result = try await client.generateContent([.text("hallo")])

        XCTAssertEqual(result, "hoi")
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
    }

    func testOpenAI_EmptyChoices_ThrowsEmptyResponse() async {
        let session = makeSession { request in
            self.ok(request, json: #"{"choices":[]}"#)
        }
        let client = OpenAICompatibleModelClient(
            flavor: .openAI, modelName: "gpt-4o-mini", systemInstruction: "",
            jsonMode: false, timeout: 10, apiKey: "sk-test", session: session
        )

        await assertThrows(client, expected: .emptyResponse)
    }

    // MARK: - Anthropic

    func testAnthropic_Success_ParsesBlocks_AndSendsHeaders() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            return self.ok(request, json: #"{"content":[{"type":"text","text":"Mooie sessie."}]}"#)
        }
        let client = AnthropicModelClient(
            modelName: "claude-haiku", systemInstruction: "Jij bent een coach.",
            jsonMode: false, timeout: 10, apiKey: "sk-ant-test", session: session
        )

        let result = try await client.generateContent([.text("analyseer")])

        XCTAssertEqual(result, "Mooie sessie.")
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = bodyJSON(captured!)
        XCTAssertEqual(body["system"] as? String, "Jij bent een coach.")
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
    }

    func testAnthropic_JSONMode_AddsPrefill_AndPrependsBrace() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            // Respons begint na de prefill-`{`.
            return self.ok(request, json: #"{"content":[{"type":"text","text":"\"plan\":1}"}]}"#)
        }
        let client = AnthropicModelClient(
            modelName: "claude-haiku", systemInstruction: "",
            jsonMode: true, timeout: 10, apiKey: "sk-ant-test", session: session
        )

        let result = try await client.generateContent([.text("plan")])

        XCTAssertEqual(result, #"{"plan":1}"#, "De prefill-{ moet weer voor de respons geplakt worden")

        let body = bodyJSON(captured!)
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.last?["role"] as? String, "assistant")
        XCTAssertEqual(messages?.last?["content"] as? String, "{")
        XCTAssertNil(body["system"], "Lege system-instructie ⇒ geen system-veld")
    }

    // MARK: - HTTP-foutmapping

    func testHTTP429_ThrowsOverloaded() async {
        let session = makeSession { self.status($0, 429) }
        let client = OpenAICompatibleModelClient(flavor: .openAI, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k", session: session)
        await assertThrows(client, expected: .overloaded)
    }

    func testHTTP503_ThrowsOverloaded() async {
        let session = makeSession { self.status($0, 503) }
        let client = OpenAICompatibleModelClient(flavor: .openAI, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k", session: session)
        await assertThrows(client, expected: .overloaded)
    }

    func testHTTP401_ThrowsAuthenticationFailed() async {
        let session = makeSession { self.status($0, 401) }
        let client = OpenAICompatibleModelClient(flavor: .openAI, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k", session: session)
        await assertThrows(client, expected: .authenticationFailed)
    }

    func testHTTP500_ThrowsHTTPStatus() async {
        let session = makeSession { self.status($0, 500) }
        let client = OpenAICompatibleModelClient(flavor: .openAI, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k", session: session)
        do {
            _ = try await client.generateContent([.text("x")])
            XCTFail("Verwachtte .http(500)")
        } catch let AIProviderError.http(status, _) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Verwachtte AIProviderError.http, kreeg \(error)")
        }
    }

    func testHTTP400_IncludesResponseBodyInError() async {
        // Regressie (Claude 400): de provider-foutbody moet meekomen zodat de
        // gebruiker de reden ziet i.p.v. een kale statuscode.
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"model: foo not found"}}"#.utf8))
        }
        let client = OpenAICompatibleModelClient(flavor: .openAI, modelName: "foo", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k", session: session)
        do {
            _ = try await client.generateContent([.text("x")])
            XCTFail("Verwachtte .http(400)")
        } catch let AIProviderError.http(status, message) {
            XCTAssertEqual(status, 400)
            XCTAssertEqual(message?.contains("model: foo not found"), true, "De foutbody hoort meegenomen te worden.")
        } catch {
            XCTFail("Verwachtte AIProviderError.http, kreeg \(error)")
        }
    }

    // MARK: - AIProviderError.isOverload

    func testIsOverload_OverloadedError_True() {
        XCTAssertTrue(AIProviderError.isOverload(AIProviderError.overloaded))
    }

    func testIsOverload_AuthError_False() {
        XCTAssertFalse(AIProviderError.isOverload(AIProviderError.authenticationFailed))
    }

    func testIsOverload_StringContaining429_True() {
        struct FakeSDKError: Error { let d = "internalError(503)" }
        XCTAssertTrue(AIProviderError.isOverload(FakeSDKError()))
    }

    func testIsOverload_PlainError_False() {
        struct PlainError: Error {}
        XCTAssertFalse(AIProviderError.isOverload(PlainError()))
    }

    // MARK: - Factory-routing

    func testFactory_RoutesProvidersToCorrectClientTypes() {
        let openAI = AIModelFactory.makeModel(provider: .openAI, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k")
        XCTAssertTrue(openAI is OpenAICompatibleModelClient)

        let mistral = AIModelFactory.makeModel(provider: .mistral, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k")
        XCTAssertTrue(mistral is OpenAICompatibleModelClient)

        let anthropic = AIModelFactory.makeModel(provider: .anthropic, modelName: "m", systemInstruction: "", jsonMode: false, timeout: 10, apiKey: "k")
        XCTAssertTrue(anthropic is AnthropicModelClient)

        let gemini = AIModelFactory.makeModel(provider: .gemini, modelName: "gemini-flash-latest", systemInstruction: "", jsonMode: true, timeout: 10, apiKey: "k")
        XCTAssertTrue(gemini is GeminiRestClient)
    }

    // MARK: - Epic #54: ProviderModelListService

    func testFetchModels_OpenAI_FiltersToChatModels_AndSendsBearer() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            let json = #"{"object":"list","data":[{"id":"gpt-5.4"},{"id":"gpt-4.1-mini"},{"id":"text-embedding-3-large"},{"id":"whisper-1"},{"id":"dall-e-3"},{"id":"gpt-4o-realtime-preview"}]}"#
            return self.ok(request, json: json)
        }
        let service = ProviderModelListService(session: session)

        let models = try await service.fetchModels(provider: .openAI, apiKey: "sk-test")

        let ids = models.map(\.id)
        XCTAssertEqual(ids, ["gpt-5.4", "gpt-4.1-mini"], "Alleen chat-modellen, aflopend gesorteerd.")
        XCTAssertFalse(ids.contains("text-embedding-3-large"))
        XCTAssertFalse(ids.contains("whisper-1"))
        XCTAssertFalse(ids.contains("dall-e-3"))
        XCTAssertFalse(ids.contains("gpt-4o-realtime-preview"))
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testFetchModels_Anthropic_KeepsAll_AndSendsHeaders_UsingDisplayName() async throws {
        var captured: URLRequest?
        let session = makeSession { request in
            captured = request
            let json = #"{"data":[{"id":"claude-sonnet-4-6","display_name":"Claude Sonnet 4.6"},{"id":"claude-haiku-4-5","display_name":"Claude Haiku 4.5"}],"has_more":false}"#
            return self.ok(request, json: json)
        }
        let service = ProviderModelListService(session: session)

        let models = try await service.fetchModels(provider: .anthropic, apiKey: "sk-ant")

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.first?.displayName, "Claude Sonnet 4.6", "display_name moet gebruikt worden.")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testFetchModels_Mistral_FiltersOnChatCapability() async throws {
        let session = makeSession { request in
            let json = #"{"data":[{"id":"mistral-large-latest","capabilities":{"completion_chat":true}},{"id":"mistral-embed","capabilities":{"completion_chat":false}}]}"#
            return self.ok(request, json: json)
        }
        let service = ProviderModelListService(session: session)

        let ids = try await service.fetchModels(provider: .mistral, apiKey: "k").map(\.id)
        XCTAssertEqual(ids, ["mistral-large-latest"])
    }

    func testFetchModels_NoChatModels_ThrowsEmptyResponse() async {
        let session = makeSession { request in
            self.ok(request, json: #"{"data":[{"id":"text-embedding-3-large"}]}"#)
        }
        let service = ProviderModelListService(session: session)
        do {
            _ = try await service.fetchModels(provider: .openAI, apiKey: "k")
            XCTFail("Verwachtte emptyResponse na filteren.")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .emptyResponse)
        } catch {
            XCTFail("Verwachtte AIProviderError.emptyResponse, kreeg \(error)")
        }
    }

    func testFetchModels_HTTP401_ThrowsAuthenticationFailed() async {
        let session = makeSession { self.status($0, 401) }
        let service = ProviderModelListService(session: session)
        do {
            _ = try await service.fetchModels(provider: .openAI, apiKey: "bad")
            XCTFail("Verwachtte authenticationFailed.")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Verwachtte AIProviderError.authenticationFailed, kreeg \(error)")
        }
    }

    func testIsChatModel_OpenAIHeuristics() {
        func item(_ id: String) -> ModelListResponse.Item {
            ModelListResponse.Item(id: id, display_name: nil, name: nil, capabilities: nil)
        }
        XCTAssertTrue(ProviderModelListService.isChatModel(provider: .openAI, item: item("gpt-5.4-mini")))
        XCTAssertTrue(ProviderModelListService.isChatModel(provider: .openAI, item: item("o3")))
        XCTAssertFalse(ProviderModelListService.isChatModel(provider: .openAI, item: item("text-embedding-3-small")))
        XCTAssertFalse(ProviderModelListService.isChatModel(provider: .openAI, item: item("gpt-4o-transcribe")))
        XCTAssertFalse(ProviderModelListService.isChatModel(provider: .openAI, item: item("gpt-image-1")))
    }

    func testFetchModels_Gemini_ReturnsBuiltInWithoutNetwork() async throws {
        // Gemini loopt via de Worker; deze service geeft de statische lijst terug.
        let service = ProviderModelListService(session: makeSession { request in
            XCTFail("Gemini hoort geen netwerk-call te doen via deze service.")
            return self.ok(request, json: "{}")
        })
        let models = try await service.fetchModels(provider: .gemini, apiKey: "k")
        XCTAssertEqual(models, AIModelCatalog.builtIn(for: .gemini).models)
    }

    // MARK: - Assert-helper

    private func assertThrows(_ client: GenerativeModelProtocol, expected: AIProviderError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.generateContent([.text("x")])
            XCTFail("Verwachtte \(expected) maar er werd niets gegooid", file: file, line: line)
        } catch let error as AIProviderError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Verwachtte AIProviderError.\(expected) maar kreeg \(error)", file: file, line: line)
        }
    }
}

/// URLProtocol-stub die elke request afvangt en een door de test bepaalde respons
/// teruggeeft. Geen netwerk, volledig deterministisch.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
