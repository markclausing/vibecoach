#if DEBUG
import Foundation

// MARK: - Sprint 26.1: UI Test Mock Environment

/// Central mock environment for XCUITest E2E tests.
///
/// Active when the app is started with the `-UITesting` launch argument.
/// Injects reproducible test data into UserDefaults so all views
/// behave deterministically — without live HealthKit, Strava or Gemini calls.
enum UITestMockEnvironment {

    // MARK: - Setup

    /// Main entry point: sets up the full mock environment.
    /// Called from AIFitnessCoachApp.init() when `-UITesting` is active.
    static func setup() {
        let defaults = UserDefaults.standard

        // If -ResetState is passed: clear all state so onboarding starts
        // from scratch again (for the Full Onboarding Flow test).
        // Epic #31 Sprint 31.1: gatekeeper migrated to `hasCompletedOnboarding`.
        if ProcessInfo.processInfo.arguments.contains("-ResetState") {
            resetAllState(defaults: defaults)
            // hasCompletedOnboarding stays false after reset → OnboardingView is shown.
        } else {
            // No reset: skip onboarding so the TabView is immediately visible.
            defaults.set(true, forKey: "hasCompletedOnboarding")
        }

        // Pin the Vibe Score to 82 (Optimally Recovered) — Epic 14.4 cache.
        defaults.set(
            "Vibe Score vandaag: 82/100 (Optimaal Hersteld). Slaap: 7u 45m. HRV: 62.5 ms.",
            forKey: "vibecoach_todayVibeScoreContext"
        )

        // Force the weather to sunny 20°C — Open-Meteo bypass via cache.
        defaults.set(
            "• Vandaag: Helder, 18–20°C, neerslag 0%, wind 8 km/u\n• Morgen: Helder, 17–20°C, neerslag 0%, wind 10 km/u",
            forKey: "vibecoach_weatherContext"
        )

        // Set a dummy API key so the Coach tab shows the chat interface
        // instead of the 'NoAPIKeyView'.
        // C-02: the key lives in the Keychain, no longer in UserDefaults.
        // Epic #53: UI tests run on the default provider (Gemini).
        if UserAPIKeyStore.read(for: .gemini).isEmpty {
            UserAPIKeyStore.write("test-ui-mock-key-do-not-call-api", for: .gemini)
        }

        // Periodisation context (for Dashboard verification in Test 4).
        defaults.set(
            "• Doel 'Marathon Amsterdam' — Fase: Build Phase · 12 weken resterend",
            forKey: "vibecoach_periodizationContext"
        )

        AppLoggers.uiTestMock.info("Mock-omgeving actief (ResetState: \(ProcessInfo.processInfo.arguments.contains("-ResetState"), privacy: .public))")
    }

    // MARK: - Reset

    /// Clears all app-specific UserDefaults keys so the app starts fresh.
    static func resetAllState(defaults: UserDefaults) {
        let keysToReset = [
            "hasCompletedOnboarding",
            "vibecoach_todayVibeScoreContext",
            "vibecoach_weatherContext",
            // C-02: legacy key — stays in the reset list so a possible
            // non-migrated leftover value is also wiped during tests.
            UserAPIKeyStore.legacyUserDefaultsKey,
            "vibecoach_aiProvider",
            "vibecoach_periodizationContext",
            "vibecoach_blueprintContext",
            "vibecoach_gapAnalysisContext",
            "vibecoach_projectionContext",
            "vibecoach_symptomContext",
            "vibecoach_nutritionContext",
            "vibecoach_lastWorkoutFeedbackContext",
            "vibecoach_lastAnalysisTimestamp",
            "vibecoach_profileUpdateNote",
            "vibecoach_recoveryPlanTimestamp",
            "latestCoachInsight",
            "latestSuggestedPlanData",
            "selectedDataSource"
        ]
        keysToReset.forEach { defaults.removeObject(forKey: $0) }
        // C-02: also clear the Keychain entries so a -ResetState run truly starts
        // blank. Epic #53: per provider + the legacy single key.
        UserAPIKeyStore.delete()
        AIProvider.allCases.forEach { UserAPIKeyStore.delete(for: $0) }
        AppLoggers.uiTestMock.info("State gereset — \(keysToReset.count, privacy: .public) sleutels gewist (+ Keychain)")
    }
}

// MARK: - Mock LLM Model

/// Mock implementation of GenerativeModelProtocol for XCUITest E2E tests.
///
/// Returns a hardcoded JSON response after 1 second instead of calling the Gemini API.
/// This saves cost and makes tests network-independent.
///
/// The response contains the key phrases the E2E tests verify on:
/// - "voorkeur opgeslagen" → Coach Memory test (Monday message)
/// - "kuit" → Coach Memory test (calf-injury message)
class UITestMockGenerativeModel: GenerativeModelProtocol {

    /// Hardcoded JSON response the coach returns in test mode.
    /// Deliberately contains the verification phrases for the Coach Memory tests.
    static let hardcodedResponse = """
    {
        "motivation": "Begrepen! Ik heb je voorkeur opgeslagen: je kunt niet op maandag trainen. Je kuit-klacht is gelogd en ik houd rekening met herstel. Je Vibe Score van 82 geeft aan dat je optimaal hersteld bent voor training.",
        "workouts": [
            {
                "dateOrDay": "Dinsdag",
                "activityType": "Hardlopen",
                "suggestedDurationMinutes": 45,
                "targetTRIMP": 60,
                "description": "Zone 2 duurloop op rustig tempo — geen maandag-sessie gepland.",
                "heartRateZone": "Zone 2",
                "targetPace": "5:30 min/km",
                "reasoning": "Zone 2 herstelloop om de aerobe basis te bewaken in de Build-fase."
            }
        ],
        "newPreferences": [
            {
                "text": "Kan niet op maandag trainen",
                "expirationDate": null
            }
        ]
    }
    """

    func generateContent(_ parts: [AIPromptPart]) async throws -> String? {
        // Simulate 1 second of network latency — realistic and fast enough for tests.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return Self.hardcodedResponse
    }
}
#endif
