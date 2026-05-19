import SwiftUI
import HealthKit

// MARK: - Epic #51-F3: HealthKit-toestemmingen per-type-overzicht
//
// Toont in Settings één rij per kritisch HK-type (Workouts, Hartslag, HRV,
// Actieve energie) met een status-badge:
//   • Groene check — `.sharingAuthorized`
//   • Grijze vraagteken — `.notDetermined` (gebruiker is verse install of
//     iOS heeft de keuze gereset)
//   • Rode 'minus' — `.sharingDenied` (expliciet geweigerd → coach kan dit
//     signaal niet meer ophalen)
//
// Bij ten minste één `.sharingDenied` verschijnt een "Open Instellingen"-
// knop die naar VibeCoach's iOS-instellingen jumpt; iOS toont daar
// automatisch de Health-permissie-deeplink.
//
// Refresh-strategie: één `.onAppear` poll + één extra refresh bij `.active`
// scenePhase zodat een gebruiker die via iOS-instellingen iets aanpast en
// terugkeert in de app meteen de juiste status ziet.

struct HealthKitPermissionsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var statuses: [HealthKitPermissionTypes.TypeStatus] = []

    private var hasDeniedTypes: Bool {
        statuses.contains(where: { $0.status == .sharingDenied })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APPLE HEALTH-TOESTEMMINGEN")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { index, status in
                    HKPermissionRow(status: status)
                    if index < statuses.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }

                if hasDeniedTypes {
                    Divider().padding(.leading, 52)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.accentColor)
                            Text("Open Instellingen om aan te passen")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { refresh() }
        }
    }

    private func refresh() {
        let store = HealthKitManager.shared.healthStore
        statuses = HealthKitPermissionTypes.criticalTypeStatuses(in: store)
    }
}

private struct HKPermissionRow: View {
    let status: HealthKitPermissionTypes.TypeStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(status.displayName)
                .font(.subheadline)

            Spacer()

            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundColor(iconColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var iconName: String {
        switch status.status {
        case .sharingAuthorized: return "checkmark.circle.fill"
        case .sharingDenied:     return "minus.circle.fill"
        default:                 return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch status.status {
        case .sharingAuthorized: return .green
        case .sharingDenied:     return .red
        default:                 return .secondary
        }
    }

    private var statusLabel: String {
        switch status.status {
        case .sharingAuthorized: return "Toegestaan"
        case .sharingDenied:     return "Geweigerd"
        default:                 return "Nog niet gekozen"
        }
    }
}
