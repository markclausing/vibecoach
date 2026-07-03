import SwiftUI
import SwiftData

// Epic #65 story 65.5: split out of WorkoutAnalysisView.swift (§5 file-split).
// Pure move — no semantic changes; shared members relaxed to internal where the
// cross-file split requires it (listed in the PR body).

// MARK: - Recent Workouts section (Dashboard)

/// Section below the TrendWidget on the Dashboard with the most recent HealthKit workouts.
/// Strava records are also shown (as context) but are not clickable — they have no
/// `WorkoutSample` data because Deep Sync only links the HealthKit source.
struct RecentWorkoutsSection: View {

    @Query private var allActivities: [ActivityRecord]
    @EnvironmentObject var themeManager: ThemeManager

    /// Number of rows we show. Default 7 — fits on one screen without dominating the scroll.
    let limit: Int

    init(limit: Int = 7) {
        self.limit = limit
        // Epic #65 story 65.2: the section only ever renders the newest `limit` rows,
        // so push the bound into the query via `fetchLimit` instead of scanning the
        // whole table and slicing in memory.
        var descriptor = FetchDescriptor<ActivityRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        _allActivities = Query(descriptor)
    }

    private var recent: [ActivityRecord] {
        Array(allActivities.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENTE WORKOUTS")
                    .font(.caption).fontWeight(.semibold)
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            if recent.isEmpty {
                Text("Nog geen workouts gevonden — synchroniseer met HealthKit of Strava.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { activity in
                        RecentWorkoutRow(activity: activity)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// One row in the "Recente Workouts" section. Clickable when `id` is parseable as a UUID
/// (= HealthKit). Strava records are shown as a static row without a chevron.
struct RecentWorkoutRow: View {
    let activity: ActivityRecord
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        // Epic 40: both HealthKit records (UUID uuidString) and Strava records
        // (numeric ID) are now clickable. WorkoutAnalysisView distinguishes them itself
        // via `UUID.forActivityRecordID(_:)` and shows samples when present — for
        // Strava records without ingested streams the existing
        // 'Nog geen samples beschikbaar' empty state appears. That is more correct than a row
        // without navigation where the user gets no feedback about why they
        // cannot tap anything.
        NavigationLink {
            WorkoutAnalysisView(activity: activity)
        } label: {
            rowContent(showChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(showChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sportIcon)
                .font(.body)
                .foregroundStyle(themeManager.primaryAccentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(activity.startDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if activity.distance > 0 {
                Text(String(format: "%.1f km", activity.distance / 1000))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        // Match TrendWidgetView styling — `Color(.systemBackground)` is white in light mode
        // and dark in dark mode (auto-adjusting), with the same subtle shadow.
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var sportIcon: String {
        switch activity.sportCategory {
        case .running:   return "figure.run"
        case .cycling:   return "figure.outdoor.cycle"
        case .swimming:  return "figure.pool.swim"
        case .strength:  return "figure.strengthtraining.traditional"
        case .walking:   return "figure.walk"
        case .triathlon: return "figure.mixed.cardio"
        case .other:     return "heart.fill"
        }
    }
}
