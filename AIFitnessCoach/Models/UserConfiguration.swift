import Foundation
import SwiftData

/// Epic #31 — Sprint 31.6: persistent configuration of a user after onboarding.
///
/// V2.0 onboarding no longer asks for a primary fitness goal — the UX flow focuses on
/// data connection (Apple Health) and signal filtering (notifications). This model
/// only stores when onboarding was completed so other features
/// (e.g. base-building, analytics) have an anchor date.
///
/// API keys are NOT stored in this model — those go via
/// `KeychainService.shared` (see `OnboardingView.completeOnboarding()`).
@Model
final class UserConfiguration {

    /// Exact moment when the user tapped "Start Coaching".
    var onboardingDate: Date

    /// Calendar day (00:00 local) on which onboarding was completed.
    /// Computed via `Calendar.current.startOfDay(for:)` — per CLAUDE.md §3
    /// (no TimeInterval math).
    var onboardingDay: Date

    init(date: Date = Date()) {
        self.onboardingDate = date
        self.onboardingDay = Calendar.current.startOfDay(for: date)
    }
}
