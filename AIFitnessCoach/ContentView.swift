import SwiftUI

/// Root-container van de app. Routeert tussen de onboarding-flow en de hoofd-app,
/// en start de proactieve coaching-engines (Epic 13) zodra de gebruiker de onboarding afrondt.
///
/// De daadwerkelijke TabView-navigatie staat in `AppTabHostView`; de dashboard-UI in `DashboardView`.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                AppTabHostView()
            } else {
                OnboardingView()
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, isOnboarded in
            // Sprint 20.2 / Epic #31: Zodra de onboarding is afgerond starten we de
            // achtergrond-engines. Dit is het eerste moment dat de gebruiker permissies
            // heeft gegeven voor HealthKit en notificaties.
            if isOnboarded {
                ProactiveNotificationService.shared.setupEngineA()
                ProactiveNotificationService.shared.scheduleEngineB()
            }
        }
    }
}
