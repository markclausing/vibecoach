import Foundation
import SwiftData

/// Epic #31 — Sprint 31.4: Persistente configuratie van een gebruiker na onboarding.
///
/// Houdt de keuzes vast die tijdens de V2.0 onboarding-flow worden gemaakt:
/// - Het gekozen primaire fitnessdoel (`UserGoal`)
/// - De datum én kalenderdag waarop de onboarding is afgerond
///
/// API-sleutels worden NIET in dit model opgeslagen — die gaan via
/// `KeychainService.shared` (zie `OnboardingView.completeOnboarding()`).
@Model
final class UserConfiguration {

    /// Ruwe opslag van het gekozen `UserGoal`. We bewaren de rawValue zodat een
    /// toekomstige migratie (nieuwe enum-cases) geen breaking change veroorzaakt.
    var primaryGoalRaw: String

    /// Exact tijdstip waarop de gebruiker op "Start Coaching" tikte.
    var onboardingDate: Date

    /// Kalenderdag (00:00 lokaal) waarop de onboarding is afgerond.
    /// Berekend via `Calendar.current.startOfDay(for:)` — conform CLAUDE.md §3
    /// (géén TimeInterval-wiskunde).
    var onboardingDay: Date

    init(primaryGoal: UserGoal, date: Date = Date()) {
        self.primaryGoalRaw = primaryGoal.rawValue
        self.onboardingDate = date
        self.onboardingDay = Calendar.current.startOfDay(for: date)
    }

    /// Type-safe accessor voor `primaryGoalRaw`. Valt terug op `.generalFitness`
    /// indien een onbekende rawValue in de store staat (bijv. na een migratie).
    var primaryGoal: UserGoal {
        get { UserGoal(rawValue: primaryGoalRaw) ?? .generalFitness }
        set { primaryGoalRaw = newValue.rawValue }
    }
}
