import SwiftUI
import Combine

/// Globale navigatiestatus van de app.
/// Dit wordt gebruikt om programmatisch van tabblad te wisselen en diepe links
/// of notificaties af te handelen.
@MainActor
class AppNavigationState: ObservableObject {
    /// De beschikbare tabbladen in de applicatie.
    enum Tab {
        case coach
        case goals
    }

    /// Het momenteel geselecteerde tabblad.
    @Published var selectedTab: Tab = .coach

    /// Een eventueel specifiek Strava Activity ID dat vanuit een notificatie
    /// is meegegeven en geanalyseerd moet worden door de coach.
    @Published var targetActivityId: Int64? = nil

    /// Optionele statische shared instance voor toegang buiten SwiftUI views (bijv. AppDelegate).
    /// Let op: Dit vereist dat we de properties updaten op de main thread.
    static let shared = AppNavigationState()

    // Init is public zodat Previews een eigen instance kunnen maken.
    init() {}

    /// Stelt de app in om een specifieke activiteit in het Coach scherm te openen.
    nonisolated func openActivityAnalysis(activityId: Int64) {
        Task { @MainActor in
            self.selectedTab = .coach
            self.targetActivityId = activityId
        }
    }
}
