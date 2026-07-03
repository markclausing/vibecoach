import Foundation

/// Story 65.3: builds and caches the AI model for the coach.
///
/// Extracted from `ChatViewModel` — `buildGenerativeModel`, the fallback builder, the
/// API-key resolution and the lazy model cache (with the Epic #51-A2 rebuild-on-name-change
/// check) now live here, on top of the existing `AIModelFactory`. The view model owns one
/// instance and asks it for `model` / `fallbackModel()`.
///
/// `@MainActor` because it is owned and mutated by the `@MainActor` `ChatViewModel`.
@MainActor
final class CoachModelProvider {

    /// The model against which requests run. Lazy: only built on the first AI request.
    /// Tests / the `-UITesting` path inject a mock via `init(injectedModel:)`.
    private var _model: GenerativeModelProtocol?

    /// Epic #51-A2: the model name for which `_model` was built. Compared with the current
    /// AppStorage choice so a Settings model-switch automatically rebuilds — otherwise the
    /// lazily-built model stayed stuck on the old name.
    private var _modelBuiltForName: String?

    /// Epic #53: the currently active provider (from AppStorage). One source so the rebuild
    /// check, the model snapshot and `buildGenerativeModel` resolve the same provider-aware
    /// model name — otherwise a rebuild loop arises with a non-Gemini provider.
    var currentProvider: AIProvider { AIProvider.current() }

    init(injectedModel: GenerativeModelProtocol? = nil) {
        self._model = injectedModel
    }

    /// True if a usable API key is configured.
    var hasAPIKey: Bool { !effectiveAPIKey().isEmpty }

    /// Epic 20 / M-04: Returns the user-configured API key. BYOK is mandatory; onboarding
    /// ensures a key is filled in before AI functionality is called. C-02: read from the
    /// Keychain via `UserAPIKeyStore`.
    func effectiveAPIKey() -> String {
        return UserAPIKeyStore.read(for: currentProvider)
    }

    /// The primary model, built lazily and rebuilt when the configured name changes.
    var model: GenerativeModelProtocol {
        if let existing = _model {
            // Mocks injected by tests or `-UITesting` have no `_modelBuiltForName`. We leave
            // those untouched — otherwise the getter would overwrite the mock with a live
            // model that hits the `hasAPIKey` gate.
            if let builtName = _modelBuiltForName,
               builtName != AIModelAppStorageKey.resolvedPrimary(for: currentProvider) {
                // Built ourselves AND the configured model name has changed → rebuild.
            } else {
                return existing
            }
        }
        let resolvedName = AIModelAppStorageKey.resolvedPrimary(for: currentProvider)
        let built = buildGenerativeModel(modelName: resolvedName)
        _model = built
        _modelBuiltForName = resolvedName
        return built
    }

    /// Builds a lighter fallback model with the same system instruction and timeout. Used
    /// invisibly as soon as the primary model returns an overload error (503/429 — peak load).
    func fallbackModel() -> GenerativeModelProtocol {
        return buildGenerativeModel(modelName: AIModelAppStorageKey.resolvedFallback(for: currentProvider))
    }

    /// Builds the model with the current API key and system instruction.
    ///
    /// Sprint 26.1: if `-UITesting` is active, a mock model is returned so the API is not
    /// called during E2E tests. Epic #35: if `modelName` is nil, the user-chosen primary
    /// model name is read from `AppStorage`.
    private func buildGenerativeModel(modelName: String? = nil) -> GenerativeModelProtocol {
        let provider = currentProvider
        let resolvedModelName = modelName ?? AIModelAppStorageKey.resolvedPrimary(for: provider)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            return UITestMockGenerativeModel()
        }
        #endif
        // Epic #37 story 37.3: the coach replies in the user's chosen language. The
        // instruction body stays English; only this directive steers the output language.
        let replyLanguage = AppLanguage.currentPromptLanguageName
        let systemInstruction = CoachPromptAssembler.systemInstruction(replyLanguage: replyLanguage)

        // Epic #53: provider-agnostic construction via the `AIModelFactory`. JSON mode on:
        // the coach response must always contain the plan JSON. Timeout 45s: enough for a
        // complex JSON-schema answer, fast enough to switch to the lite fallback on overload.
        return AIModelFactory.makeModel(
            provider: provider,
            modelName: resolvedModelName,
            systemInstruction: systemInstruction,
            jsonMode: true,
            timeout: 45,
            apiKey: UserAPIKeyStore.read(for: provider)
        )
    }
}
