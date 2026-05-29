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
        await assertThrows(client, expected: .http(status: 500))
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
        XCTAssertTrue(gemini is RealGenerativeModel)
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
