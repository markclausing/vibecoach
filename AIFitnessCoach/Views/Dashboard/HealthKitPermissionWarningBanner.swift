import SwiftUI
import HealthKit

// MARK: - Epic 38 Story 38.2: HealthKitPermissionWarningBanner

/// "Silent sync" banner: appears when the last HK sync yielded 0 workouts
/// and the workout permission is not explicitly `.sharingAuthorized`.
/// Prevents the user from walking around for days with an empty dashboard without
/// knowing it is due to HealthKit permissions. A pure-Swift logic call
/// to `HealthKitSyncStatusEvaluator` keeps the decision testable without an
/// `HKHealthStore` mock.
struct HealthKitPermissionWarningBanner: View {
    /// Cache from `AppTabHostView.runHealthKitAutoSync` / `SettingsView` historical sync.
    /// `-1` = sentinel "never synced yet" → no banner (avoids a false positive on the
    /// very first app launch before the first auto-sync cycle).
    @AppStorage(AppStorageKeys.lastHKWorkoutsCount) private var lastHKWorkoutsCount: Int = -1
    @State private var workoutAuthStatus: HKAuthorizationStatus = .notDetermined

    private var shouldShow: Bool {
        lastHKWorkoutsCount >= 0 &&
            HealthKitSyncStatusEvaluator.shouldWarn(
                workoutCount: lastHKWorkoutsCount,
                workoutAuthStatus: workoutAuthStatus)
    }

    var body: some View {
        Group {
            if shouldShow {
                DashboardBannerView(icon: "exclamationmark.icloud", color: .red) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Geen HealthKit-data gevonden")
                            .font(.subheadline.bold())
                        Text("Controleer of de app toestemming heeft voor Workouts en Hartslag — anders blijft het Dashboard leeg.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Instellingen")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .onAppear {
            workoutAuthStatus = HealthKitManager.shared.healthStore.authorizationStatus(for: .workoutType())
        }
    }
}
