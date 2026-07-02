import SwiftUI
import HealthKit
import UserNotifications

/// Epic #62 stories 62.3 + 62.5 — a single overview of every permission and background engine,
/// so a user can see at a glance what is connected and why the coach might be quiet. Reached via
/// a NavigationLink in Settings. Decision logic lives in the pure `PermissionStatusEvaluator`;
/// this view only reads the live framework state and renders the verdict + an action.
struct PermissionStatusView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var healthKitLevel: PermissionStatusEvaluator.AccessLevel = .notRequested
    @State private var notificationLevel: PermissionStatusEvaluator.AccessLevel = .notRequested
    @State private var engineA: PermissionStatusEvaluator.EngineStatus = .inactive
    @State private var engineB: PermissionStatusEvaluator.EngineStatus = .inactive
    @State private var engineAError: String?
    @State private var engineBError: String?
    /// Epic #62 story 62.4: features that degrade because a critical HealthKit signal was never granted.
    @State private var hkDegradedFeatures: [HealthKitPermissionAudit.DegradedFeature] = []

    var body: some View {
        Form {
            Section(header: Text("Toestemmingen"),
                    footer: Text("HealthKit voedt je Vibe Score en trainingsanalyse; notificaties zijn optioneel en sturen alleen een seintje bij afwijkingen.")) {
                permissionRow(
                    icon: "heart.text.square.fill",
                    title: "Apple Health",
                    level: healthKitLevel,
                    action: healthKitLevel == .granted ? nil : .openSettings
                )
                // Epic #62 story 62.4: spell out what a missing HealthKit signal costs.
                if !hkDegradedFeatures.isEmpty {
                    Label("Hierdoor mis je: \(degradedFeaturesText)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                permissionRow(
                    icon: "bell.badge.fill",
                    title: "Notificaties",
                    level: notificationLevel,
                    action: notificationAction
                )
            }

            Section(header: Text("Achtergrond-coach"),
                    footer: Text("Engine A reageert op nieuwe workouts, Engine B doet een dagelijkse check op inactiviteit. Beide draaien alleen met de juiste toestemmingen.")) {
                engineRow(icon: "figure.run", title: "Engine A — workout-trigger", status: engineA, error: engineAError)
                engineRow(icon: "clock.arrow.circlepath", title: "Engine B — dagelijkse check", status: engineB, error: engineBError)
            }
        }
        .navigationTitle("Toestemmingen & achtergrond")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    // MARK: - Rows

    private enum RowAction { case openSettings, requestNotifications }

    private var notificationAction: RowAction? {
        switch notificationLevel {
        case .granted:      return nil
        case .notRequested: return .requestNotifications
        case .denied, .partial: return .openSettings
        }
    }

    private func permissionRow(icon: String, title: String, level: PermissionStatusEvaluator.AccessLevel, action: RowAction?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color(for: level))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.body)
                Text(label(for: level)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button(action == .requestNotifications ? "Sta toe" : "Open Instellingen") {
                    perform(action)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    private func engineRow(icon: String, title: String, status: PermissionStatusEvaluator.EngineStatus, error: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color(for: status))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.body)
                Text(label(for: status)).font(.caption).foregroundStyle(.secondary)
                if status == .failed, let error {
                    // Framework error string only — non-identifying (§11).
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: status == .active ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(color(for: status))
        }
    }

    // MARK: - Level → copy/colour

    private func color(for level: PermissionStatusEvaluator.AccessLevel) -> Color {
        switch level {
        case .granted:      return .green
        case .partial:      return .orange
        case .denied:       return .red
        case .notRequested: return .secondary
        }
    }

    private func color(for status: PermissionStatusEvaluator.EngineStatus) -> Color {
        switch status {
        case .active:   return .green
        case .failed:   return .red
        case .inactive: return .secondary
        }
    }

    private func label(for level: PermissionStatusEvaluator.AccessLevel) -> String {
        switch level {
        case .granted:      return String(localized: "Gekoppeld")
        case .partial:      return String(localized: "Gekoppeld, maar geen data — controleer toegang in Apple Health")
        case .denied:       return String(localized: "Geweigerd")
        case .notRequested: return String(localized: "Niet gekoppeld")
        }
    }

    private func label(for status: PermissionStatusEvaluator.EngineStatus) -> String {
        switch status {
        case .active:   return String(localized: "Actief")
        case .failed:   return String(localized: "Registratie mislukt")
        case .inactive: return String(localized: "Niet actief")
        }
    }

    // MARK: - Degraded-features (Epic #62 story 62.4)

    /// The critical HealthKit signals that were never asked (reliable for read types, unlike a
    /// post-grant denial which HealthKit hides). Maps each to its `CriticalSignal`.
    private static func missingCriticalSignals(in store: HKHealthStore) -> Set<HealthKitPermissionAudit.CriticalSignal> {
        let pairs: [(HKObjectType?, HealthKitPermissionAudit.CriticalSignal)] = [
            (.workoutType(), .workouts),
            (HKQuantityType.quantityType(forIdentifier: .heartRate), .heartRate),
            (HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN), .hrv),
            (HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned), .activeEnergy)
        ]
        var missing: Set<HealthKitPermissionAudit.CriticalSignal> = []
        for (type, signal) in pairs where type.map({ store.authorizationStatus(for: $0) }) == .notDetermined {
            missing.insert(signal)
        }
        return missing
    }

    private var degradedFeaturesText: String {
        hkDegradedFeatures.map(Self.label(for:)).joined(separator: ", ")
    }

    private static func label(for feature: HealthKitPermissionAudit.DegradedFeature) -> String {
        switch feature {
        case .schedule:       return String(localized: "trainingsschema")
        case .intensityZones: return String(localized: "intensiteitszones")
        case .vibeScore:      return String(localized: "Vibe Score")
        case .loadEstimate:   return String(localized: "belastingsschatting")
        }
    }

    // MARK: - Actions

    private func perform(_ action: RowAction) {
        switch action {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .requestNotifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                Task { @MainActor in refresh() }
            }
        }
    }

    // MARK: - Live state read

    private func refresh() {
        let store = HealthKitManager.shared.healthStore
        let available = HKHealthStore.isHealthDataAvailable()
        let anyCriticalNotDetermined = !HealthKitPermissionTypes.criticalNotDetermined(in: store).isEmpty
        let rawCount = UserDefaults.standard.integer(forKey: AppStorageKeys.lastHKWorkoutsCount)
        // -1 (or absent) = no sync recorded yet → unknown; otherwise the cached count.
        let lastWorkoutCount: Int? = rawCount < 0 ? nil : rawCount
        let hkLevel = PermissionStatusEvaluator.healthKitLevel(
            available: available,
            anyCriticalNotDetermined: anyCriticalNotDetermined,
            lastWorkoutCount: lastWorkoutCount
        )
        healthKitLevel = hkLevel

        // Epic #62 story 62.4: which features degrade because a critical signal was never granted.
        // Only `.notDetermined` is reliable for read types (HealthKit hides read-grant state).
        let missingSignals = Self.missingCriticalSignals(in: store)
        hkDegradedFeatures = HealthKitPermissionAudit.degradedFeatures(missing: missingSignals)
            .sorted { $0.rawValue < $1.rawValue }

        engineAError = ProactiveNotificationService.engineALastError
        engineBError = ProactiveNotificationService.engineBLastError
        engineA = PermissionStatusEvaluator.engineAStatus(
            healthKitGranted: available && !anyCriticalNotDetermined,
            backgroundDeliveryActive: ProactiveNotificationService.engineABackgroundActive,
            hasError: engineAError != nil
        )
        engineB = PermissionStatusEvaluator.engineBStatus(
            scheduled: ProactiveNotificationService.engineBScheduled,
            hasError: engineBError != nil
        )

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in
                notificationLevel = PermissionStatusEvaluator.notificationLevel(authorized: authorized, denied: denied)
            }
        }
    }
}
