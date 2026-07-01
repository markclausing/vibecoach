import SwiftUI

// MARK: - Epic 20: AI Coach Configuration (BYOK)

/// Settings screen where the user configures their own AI provider and API key.
/// The key is stored in AppStorage (locally on the device, not shared).
struct AIProviderSettingsView: View {
    @AppStorage("vibecoach_aiProvider")  private var providerRaw: String = AIProvider.gemini.rawValue
    // Epic #35: chosen primary & fallback Gemini models. Read by
    // `ChatViewModel.buildGenerativeModel`. Defaults match the values that were
    // hardcoded before Epic #35 so that an existing installation without an explicit
    // choice keeps using exactly the same models.
    @AppStorage(AIModelAppStorageKey.primary)
    private var primaryModelId: String = AIModelAppStorageKey.defaultPrimary
    @AppStorage(AIModelAppStorageKey.fallback)
    private var fallbackModelId: String = AIModelAppStorageKey.defaultFallback
    // C-02: the API key is read from / written to the Keychain
    // (see `UserAPIKeyStore`). `@State` holds the live binding with the SecureField;
    // `.onAppear` loads, `.onChange` persists.
    @State                               private var apiKey: String = ""
    @EnvironmentObject private var themeManager: ThemeManager

    /// Sprint 31.7: state machine for the minimal validation ping.
    /// The last tested key is tracked so we automatically reset the feedback block
    /// when the user changes their key.
    @State private var testState: APIKeyTestState = .idle
    @State private var testedKey: String = ""

    /// Epic #35 — model catalogue (via Cloudflare Worker) + fetch status.
    /// `hasAttemptedInitialLoad` distinguishes "never attempted" (show
    /// only a ProgressView) from "attempted, now live or fallback" (show
    /// pickers). This prevents the user from seeing a picker filled with
    /// the twelve-entry `builtInFallback` while the real list is still on its way.
    @State private var modelCatalog: AIModelCatalog = .builtInFallback
    @State private var isLoadingCatalog: Bool = false
    @State private var hasAttemptedInitialLoad: Bool = false
    @State private var catalogError: String?
    private let catalogService = AIModelCatalogService()

    /// Epic #53 (53.6): model choice for non-Gemini providers, from the static
    /// `AIModelCatalog.builtIn(for:)`. Gemini uses the dynamic Worker
    /// catalogue above; these two @State fields are loaded/persisted per provider
    /// via the provider-suffixed `AIModelAppStorageKey` keys.
    @State private var customPrimaryModel: String = ""
    @State private var customFallbackModel: String = ""

    /// Epic #54: live model catalogue per non-Gemini provider, fetched directly
    /// with the user key. Starts as the static `builtIn` list and is replaced
    /// once the live `/v1/models` fetch completes (falls back silently on error/empty key).
    @State private var providerModelCatalog: [AIModelDescriptor] = []
    @State private var isLoadingProviderModels: Bool = false
    @State private var providerModelsError: String?
    @State private var keyHelpURL: IdentifiableURL?
    private let providerModelListService = ProviderModelListService()

    /// Epic #62 story 62.2: persists the "key works" verdict per provider so it survives a
    /// provider switch and an app restart (stores only a SHA256 fingerprint of the key).
    private let testStatusStore = APIKeyTestStatusStore()

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .gemini
    }

    /// The feedback block is only valid for the key that was entered at the moment
    /// of the test. After typing, the verdict expires.
    private var showTestResult: Bool {
        testState != .idle && testedKey == apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            // Provider picker
            Section(header: Text("AI Provider")) {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // API key input
            Section(
                header: Text("API Sleutel"),
                footer: VStack(alignment: .leading, spacing: 6) {
                    Text("VibeCoach gebruikt jouw eigen API-sleutel om de AI te activeren. De sleutel wordt uitsluitend lokaal op dit apparaat opgeslagen en nooit gedeeld met derden.")
                        .font(.caption)
                    if let url = selectedProvider.getKeyURL {
                        Button("Hoe kom ik aan een sleutel? →") {
                            keyHelpURL = IdentifiableURL(url: url)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            ) {
                SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("APIKeyField")

                // Epic #62 story 62.2: warn when the pasted key's prefix belongs to a different
                // provider (e.g. an sk-… OpenAI key under Gemini) — a common cause of "invalid key".
                if APIKeyInputValidator.isProviderMismatch(key: apiKey, selected: selectedProvider) {
                    Label("Deze sleutel lijkt van een andere provider. Controleer of je provider en sleutel bij elkaar horen.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("APIKeyProviderMismatchWarning")
                }
            }

            // Status indicator
            if !apiKey.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.primaryAccentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sleutel geconfigureerd")
                                .fontWeight(.medium)
                            Text("Je AI Coach is actief en klaar voor gebruik.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Epic #35 — Model selection. Only for Gemini (dynamic Worker
            // catalogue). The provider-specific model pickers for OpenAI/Claude/
            // Mistral follow in Epic #53 story 53.6; until then those providers use
            // their curated default model (`AIModelCatalog.builtIn(for:)`).
            if selectedProvider == .gemini {
                Section(
                    header: Text("Gemini Modellen"),
                    footer: modelPickerFooter
                ) {
                    if !hasAttemptedInitialLoad {
                        // Initial load: show only a ProgressView so the
                        // user doesn't have to choose from the builtInFallback
                        // while the real list is still on its way.
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Modellen ophalen…")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityIdentifier("GeminiModelsLoading")
                    } else {
                        Picker("Primair model", selection: $primaryModelId) {
                            ForEach(modelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .accessibilityIdentifier("PrimaryGeminiModelPicker")

                        Picker("Fallback model", selection: $fallbackModelId) {
                            ForEach(modelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .accessibilityIdentifier("FallbackGeminiModelPicker")
                    }
                }
            } else {
                // Epic #54: dynamic model picker per non-Gemini provider. The list
                // is fetched live with the user key (`loadProviderModels`); as long
                // as that runs — or on an error/empty key — it shows the static
                // `AIModelCatalog.builtIn(for:)` as a safety net so the picker is never empty.
                let models = providerModelCatalog.isEmpty
                    ? AIModelCatalog.builtIn(for: selectedProvider).models
                    : providerModelCatalog
                Section(header: Text("\(selectedProvider.displayName) modellen"),
                        footer: providerModelsFooter) {
                    Picker("Primair model", selection: $customPrimaryModel) {
                        ForEach(models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .accessibilityIdentifier("PrimaryProviderModelPicker")

                    Picker("Fallback model", selection: $customFallbackModel) {
                        ForEach(models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .accessibilityIdentifier("FallbackProviderModelPicker")
                }
            }

            // Sprint 31.7: Test ping — validates the key with a minimal
            // auth call against Gemini. The waterfall (primary → fallback on 503/429)
            // lives in `APIKeyValidator` so that a valid key isn't wrongly marked
            // as invalid during a Google overload.
            if !apiKey.isEmpty {
                Section(footer: testFeedbackFooter) {
                    Button {
                        testAPIKey()
                    } label: {
                        HStack {
                            if testState == .testing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 2)
                                Text("Sleutel testen…")
                            } else {
                                Image(systemName: "bolt.circle")
                                Text("Test deze sleutel")
                            }
                            Spacer()
                        }
                    }
                    .disabled(testState == .testing)
                    .accessibilityIdentifier("TestAPIKeyButton")
                }
            }
        }
        .navigationTitle("AI Coach Configuratie")
        .sheet(item: $keyHelpURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        // C-02: Keychain-linked load/save around the SecureField.
        .onAppear {
            apiKey = UserAPIKeyStore.read(for: selectedProvider)
            // Epic #62 story 62.2: restore a previously persisted "key works" verdict.
            restoreTestVerdict()
            loadCustomModels()
            loadModelCatalog()
            loadProviderModels()
        }
        .onChange(of: apiKey) { _, newValue in
            // Epic #62 story 62.2: auto-trim a pasted key — stray spaces/newlines otherwise
            // cause a silent auth failure. Re-enter once with the clean value, then persist.
            let clean = APIKeyInputValidator.sanitize(newValue)
            if clean != newValue {
                apiKey = clean
                return
            }
            UserAPIKeyStore.write(clean, for: selectedProvider)
            // The verdict is only valid for the exact validated key — re-derive for the current one.
            restoreTestVerdict()
        }
        .onChange(of: providerRaw) { _, _ in
            // Epic #53: on a provider switch, show the key + model choice from the new
            // provider slot. Epic #62 story 62.2: restore the persisted verdict for that
            // provider's key instead of always resetting to idle.
            apiKey = UserAPIKeyStore.read(for: selectedProvider)
            loadCustomModels()
            restoreTestVerdict()
            // Epic #54: fetch the live model list of the new provider.
            loadProviderModels()
        }
        .onChange(of: testState) { _, newState in
            // Epic #54: a just-validated key unlocks the live model list —
            // refresh so the user immediately sees their real models.
            if newState == .valid { loadProviderModels() }
        }
        // Epic #53 (53.6): persist the non-Gemini model choice separated per provider.
        // Gemini runs via the @AppStorage bindings above, so we skip those.
        .onChange(of: customPrimaryModel) { _, newValue in
            guard !newValue.isEmpty, selectedProvider != .gemini else { return }
            UserDefaults.standard.set(newValue, forKey: AIModelAppStorageKey.primaryKey(for: selectedProvider))
        }
        .onChange(of: customFallbackModel) { _, newValue in
            guard !newValue.isEmpty, selectedProvider != .gemini else { return }
            UserDefaults.standard.set(newValue, forKey: AIModelAppStorageKey.fallbackKey(for: selectedProvider))
        }
    }

    /// Loads the stored (or default) model choice for the active non-Gemini
    /// provider into the picker bindings. For Gemini this is a no-op that is ignored
    /// by the `selectedProvider != .gemini` guard in the persist handlers.
    private func loadCustomModels() {
        customPrimaryModel = AIModelAppStorageKey.resolvedPrimary(for: selectedProvider)
        customFallbackModel = AIModelAppStorageKey.resolvedFallback(for: selectedProvider)
    }

    /// Epic #54: fetches the live model list of the active non-Gemini provider
    /// with the user key. Starts with the static list (picker never empty) and
    /// replaces it once the fetch succeeds. Resets the stored choice to a valid
    /// one if it no longer appears in the live list (e.g. deprecated).
    private func loadProviderModels() {
        guard selectedProvider != .gemini else { return }
        let provider = selectedProvider
        providerModelCatalog = AIModelCatalog.builtIn(for: provider).models

        let key = UserAPIKeyStore.read(for: provider)
        guard !key.isEmpty else { return }

        isLoadingProviderModels = true
        providerModelsError = nil
        Task {
            do {
                let models = try await providerModelListService.fetchModels(provider: provider, apiKey: key)
                await MainActor.run {
                    isLoadingProviderModels = false
                    // Provider may have switched during the fetch — ignore stale result.
                    guard selectedProvider == provider, !models.isEmpty else { return }
                    providerModelCatalog = models

                    let ids = Set(models.map(\.id))
                    let builtIn = AIModelCatalog.builtIn(for: provider)
                    if !ids.contains(customPrimaryModel) {
                        customPrimaryModel = ids.contains(builtIn.defaultPrimary) ? builtIn.defaultPrimary : (models.first?.id ?? customPrimaryModel)
                    }
                    if !ids.contains(customFallbackModel) {
                        customFallbackModel = ids.contains(builtIn.defaultFallback) ? builtIn.defaultFallback : (models.last?.id ?? customFallbackModel)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingProviderModels = false
                    guard selectedProvider == provider else { return }
                    // Epic #54: show the failure reason instead of silently falling back, so a
                    // scope/auth problem (e.g. an OpenAI key without Models read access)
                    // is visible. The picker keeps showing the static fallback.
                    providerModelsError = Self.describeModelListError(error)
                }
            }
        }
    }

    /// Short, user-readable reason why the live model list could not load.
    private static func describeModelListError(_ error: Error) -> String {
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .authenticationFailed:
                return "je sleutel mag de modellijst niet ophalen (controleer of de key 'Models'-leesrecht heeft)"
            case .overloaded:
                return "provider tijdelijk overbelast"
            case .emptyResponse:
                return "geen chat-modellen herkend in de lijst"
            case .decodingFailed:
                return "onverwacht lijstformaat"
            case .http(let status, let message):
                return "HTTP \(status)\(message.map { ": \($0)" } ?? "")"
            case .contentBlocked:
                return "verzoek geblokkeerd"
            }
        }
        if let urlError = error as? URLError {
            return "netwerkprobleem (\(urlError.code.rawValue))"
        }
        return error.localizedDescription
    }

    @ViewBuilder
    private var providerModelsFooter: some View {
        if isLoadingProviderModels {
            Text("Modellen van \(selectedProvider.displayName) ophalen met je sleutel…")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Epic #54: without a key we can't query /v1/models → built-in list.
            Text("Voer je \(selectedProvider.displayName)-sleutel in (en test 'm) om je beschikbare modellen live te laden. Tot dan tonen we een ingebouwde lijst.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if let err = providerModelsError {
            Text("Live lijst niet beschikbaar — \(err). Ingebouwde lijst getoond.")
                .font(.caption)
                .foregroundColor(.orange)
        } else {
            Text("Live opgehaald met je sleutel. Lukt dat niet, dan tonen we een ingebouwde lijst.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Epic #35 — Model catalogue

    /// Fetches the model list from the Cloudflare Worker. Fails silently to the
    /// built-in fallback so the picker is never empty; any error does appear
    /// as a subtle message below the pickers.
    private func loadModelCatalog() {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogError = nil

        Task {
            do {
                let catalog = try await catalogService.fetchCatalog()
                await MainActor.run {
                    self.modelCatalog = catalog
                    self.isLoadingCatalog = false
                    self.hasAttemptedInitialLoad = true
                    // If the stored choice is no longer in the catalogue
                    // — model is deprecated or a typo — silently fall back on the
                    // server-recommended default. Prevents the app from
                    // sending a non-existent model to Gemini.
                    let ids = Set(catalog.models.map(\.id))
                    if !ids.contains(self.primaryModelId) {
                        self.primaryModelId = catalog.defaultPrimary
                    }
                    if !ids.contains(self.fallbackModelId) {
                        self.fallbackModelId = catalog.defaultFallback
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingCatalog = false
                    self.hasAttemptedInitialLoad = true
                    self.catalogError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var modelPickerFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("De coach begint bij het primaire model. Bij overbelasting (503/429) schakelt hij automatisch over op het fallback-model.")
                .font(.caption)
            if let err = catalogError {
                Text("Kon live-lijst niet ophalen — fallback op ingebouwde modellen gebruikt. (\(err))")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Test feedback (inline in footer)

    @ViewBuilder
    private var testFeedbackFooter: some View {
        if showTestResult {
            switch testState {
            case .idle, .testing:
                EmptyView()
            case .valid:
                feedbackRow(icon: "checkmark.seal.fill",
                            color: .green,
                            title: "Sleutel werkt",
                            detail: "\(selectedProvider.displayName) heeft de sleutel geaccepteerd.")
            case .invalidKey:
                feedbackRow(icon: "xmark.octagon.fill",
                            color: .red,
                            title: "Sleutel ongeldig",
                            detail: "\(selectedProvider.displayName) weigert deze sleutel. Controleer of je hem volledig hebt geplakt.")
            case .rateLimited:
                feedbackRow(icon: "hourglass.circle.fill",
                            color: .orange,
                            title: "Model overbelast",
                            detail: "De servers van \(selectedProvider.displayName) zijn vol. Je sleutel kán geldig zijn — probeer zo nog eens.")
            case .network:
                feedbackRow(icon: "wifi.exclamationmark",
                            color: .orange,
                            title: "Geen verbinding",
                            detail: "Controleer je internetverbinding en probeer opnieuw.")
            case .unknown(let message):
                feedbackRow(icon: "exclamationmark.triangle.fill",
                            color: .orange,
                            title: "Onverwachte fout",
                            detail: message)
            }
        }
    }

    private func feedbackRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Test action

    func testAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        testState = .testing
        testedKey = trimmed
        let provider = selectedProvider

        Task {
            let result = await APIKeyValidator.validate(trimmed, provider: provider)
            await MainActor.run {
                switch result {
                case .valid:            testState = .valid
                case .invalidKey:       testState = .invalidKey
                case .rateLimited:      testState = .rateLimited
                case .network:          testState = .network
                case .unknown(let msg): testState = .unknown(msg)
                }
                // Epic #62 story 62.2: persist a positive verdict (survives provider switch +
                // app restart); clear it on a definitive rejection. Transient states
                // (rateLimited/network) leave any earlier verdict untouched.
                switch result {
                case .valid:      testStatusStore.markValidated(key: trimmed, for: provider)
                case .invalidKey: testStatusStore.clear(for: provider)
                default:          break
                }
            }
        }
    }

    /// Epic #62 story 62.2: shows a persisted "key works" verdict when the current key matches
    /// the last one validated for this provider; otherwise resets to idle (unless mid-test).
    private func restoreTestVerdict() {
        let clean = APIKeyInputValidator.sanitize(apiKey)
        if testStatusStore.isValidated(key: clean, for: selectedProvider) {
            testedKey = clean
            testState = .valid
        } else if testState != .testing {
            testState = .idle
        }
    }
}

/// Internal UI state for testing the key. Separate from
/// `APIKeyValidationResult` so we can also show `.idle` and `.testing`.
private enum APIKeyTestState: Equatable {
    case idle
    case testing
    case valid
    case invalidKey
    case rateLimited
    case network
    case unknown(String)
}
