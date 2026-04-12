#if DEBUG
import Foundation
import GoogleGenerativeAI

// MARK: - Sprint 26.1: UI Test Mock Environment

/// Centrale mock-omgeving voor XCUITest E2E-tests.
///
/// Wordt actief als de app gestart is met het `-UITesting` launch argument.
/// Injecteert reproduceerbare testdata in UserDefaults zodat alle views
/// deterministisch gedrag vertonen — zonder live HealthKit-, Strava- of Gemini-calls.
enum UITestMockEnvironment {

    // MARK: - Setup

    /// Hoofdingang: zet de volledige mock-omgeving op.
    /// Aangeroepen vanuit AIFitnessCoachApp.init() als `-UITesting` actief is.
    static func setup() {
        let defaults = UserDefaults.standard

        // Als -ResetState meegegeven is: wis alle state zodat de onboarding opnieuw
        // vanaf nul begint (voor de Full Onboarding Flow test).
        if ProcessInfo.processInfo.arguments.contains("-ResetState") {
            resetAllState(defaults: defaults)
            // hasSeenOnboarding blijft na reset op false → OnboardingView wordt getoond.
        } else {
            // Geen reset: sla de onboarding over zodat de TabView direct zichtbaar is.
            defaults.set(true, forKey: "hasSeenOnboarding")
        }

        // Zet de Vibe Score vast op 82 (Optimaal Hersteld) — Epic 14.4 cache.
        defaults.set(
            "Vibe Score vandaag: 82/100 (Optimaal Hersteld). Slaap: 7u 45m. HRV: 62.5 ms.",
            forKey: "vibecoach_todayVibeScoreContext"
        )

        // Forceer het weer naar zonnig 20°C — Open-Meteo bypass via cache.
        defaults.set(
            "• Vandaag: Helder, 18–20°C, neerslag 0%, wind 8 km/u\n• Morgen: Helder, 17–20°C, neerslag 0%, wind 10 km/u",
            forKey: "vibecoach_weatherContext"
        )

        // Zet een dummy API-sleutel zodat de Coach tab de chatinterface toont
        // in plaats van de 'NoAPIKeyView'.
        if defaults.string(forKey: "vibecoach_userAPIKey")?.isEmpty ?? true {
            defaults.set("test-ui-mock-key-do-not-call-api", forKey: "vibecoach_userAPIKey")
        }

        // Periodisatiecontext (voor Dashboard verificatie in Test 4).
        defaults.set(
            "• Doel 'Marathon Amsterdam' — Fase: Build Phase · 12 weken resterend",
            forKey: "vibecoach_periodizationContext"
        )

        print("✅ UITestMockEnvironment: Mock-omgeving actief (ResetState: \(ProcessInfo.processInfo.arguments.contains("-ResetState")))")
    }

    // MARK: - Reset

    /// Wist alle app-specifieke UserDefaults-sleutels zodat de app als nieuw start.
    static func resetAllState(defaults: UserDefaults) {
        let keysToReset = [
            "hasSeenOnboarding",
            "vibecoach_todayVibeScoreContext",
            "vibecoach_weatherContext",
            "vibecoach_userAPIKey",
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
            "selectedDataSource",
        ]
        keysToReset.forEach { defaults.removeObject(forKey: $0) }
        print("🔄 UITestMockEnvironment: State gereset — \(keysToReset.count) sleutels gewist")
    }
}

// MARK: - Mock LLM Model

/// Mock implementatie van GenerativeModelProtocol voor XCUITest E2E-tests.
///
/// Retourneert na 1 seconde een hardcoded JSON-response in plaats van de Gemini API
/// aan te roepen. Dit bespaart kosten en maakt tests netwerk-onafhankelijk.
///
/// De response bevat de sleutelzinnen die de E2E-tests op verifiëren:
/// - "voorkeur opgeslagen" → Coach Memory test (maandag-bericht)
/// - "kuit" → Coach Memory test (kuit-blessure bericht)
class UITestMockGenerativeModel: GenerativeModelProtocol {

    /// Hardcoded JSON-response die de coach teruggeeft in test-modus.
    /// Bevat bewust de verificatiezinnen voor Coach Memory tests.
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

    func generateContent(_ parts: [ModelContent.Part]) async throws -> String? {
        // Simuleer 1 seconde netwerklatentie — realistisch en snel genoeg voor tests.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return Self.hardcodedResponse
    }
}
#endif
