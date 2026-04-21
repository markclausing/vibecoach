import Foundation
import SwiftData

/// Epic #31 — Sprint 31.6: Persistente configuratie van een gebruiker na onboarding.
///
/// V2.0 onboarding vraagt géén primair fitnessdoel meer — de UX-flow focust op
/// dataverbinding (Apple Health) en signaal-filtering (notificaties). Dit model
/// bewaart enkel wanneer de onboarding is afgerond zodat andere features
/// (bijv. base-building, analytics) een ankerdatum hebben.
///
/// API-sleutels worden NIET in dit model opgeslagen — die gaan via
/// `KeychainService.shared` (zie `OnboardingView.completeOnboarding()`).
@Model
final class UserConfiguration {

    /// Exact tijdstip waarop de gebruiker op "Start Coaching" tikte.
    var onboardingDate: Date

    /// Kalenderdag (00:00 lokaal) waarop de onboarding is afgerond.
    /// Berekend via `Calendar.current.startOfDay(for:)` — conform CLAUDE.md §3
    /// (géén TimeInterval-wiskunde).
    var onboardingDay: Date

    init(date: Date = Date()) {
        self.onboardingDate = date
        self.onboardingDay = Calendar.current.startOfDay(for: date)
    }
}
