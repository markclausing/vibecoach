import SwiftUI

/// Root container of the app. Routes between the onboarding flow and the main app,
/// and starts the proactive coaching engines (Epic 13) once the user completes onboarding.
///
/// The actual TabView navigation lives in `AppTabHostView`; the dashboard UI in `DashboardView`.
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
            // Sprint 20.2 / Epic #31: Once onboarding is complete we start the
            // background engines. This is the first moment the user has granted
            // permissions for HealthKit and notifications.
            if isOnboarded {
                ProactiveNotificationService.shared.setupEngineA()
                ProactiveNotificationService.shared.scheduleEngineB()
            }
        }
    }
}
