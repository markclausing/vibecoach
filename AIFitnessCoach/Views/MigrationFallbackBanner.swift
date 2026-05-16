import SwiftUI

/// Toont een banner op het Dashboard zodra de SwiftData-migratie tijdens de
/// laatste app-launch is gefaald en de fresh-DB-fallback (CLAUDE.md §12) is
/// geactiveerd. De gebruiker leert daardoor dat doelen, voorkeuren en
/// blessure-meldingen lokaal-only data zijn — workouts uit HealthKit en
/// Strava re-syncen vanzelf en zijn niet beïnvloed.
///
/// Pollt elke `.onAppear` de `MigrationFallbackStore`-flag (geen reactieve
/// publisher nodig — de flag wordt enkel tijdens app-init geschreven). Bij
/// "Sluit" wist de banner de flag en verdwijnt definitief tot de volgende
/// fallback.
struct MigrationFallbackBanner: View {
    private let store: MigrationFallbackStore

    @State private var fallbackDate: Date?

    init(store: MigrationFallbackStore = MigrationFallbackStore()) {
        self.store = store
    }

    var body: some View {
        Group {
            if let date = fallbackDate {
                DashboardBannerView(icon: "arrow.triangle.2.circlepath", color: .orange) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App-data opnieuw opgebouwd")
                            .font(.subheadline.bold())
                        Text("Bij de update van \(Self.dateFormatter.string(from: date)) zijn enkele lokale instellingen opnieuw opgebouwd. Je workouts uit Apple Health en Strava zijn niet beïnvloed — controleer wel je doelen en eventuele blessures.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            store.clear()
                            withAnimation(.easeOut(duration: 0.25)) {
                                fallbackDate = nil
                            }
                        } label: {
                            Text("Begrepen, sluit")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .onAppear {
            fallbackDate = store.fallbackDate
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
