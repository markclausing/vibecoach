import Foundation

// MARK: - Epic #65 Story 65.2: Bounded data access

/// Central definition of the rolling time-windows that bound the app's full-table
/// `@Query`s (`ActivityRecord`, `DailyReadiness`, `Symptom`). Extracting the cutoffs
/// here — instead of scattering `Calendar.date(byAdding:)` calls across views — makes
/// them unit-testable (§6) and gives one place to widen a window if a consumer grows.
///
/// - All cutoffs are **Calendar-based** (§3: never `TimeInterval` second-math, which
///   drifts across DST / leap boundaries).
/// - They are computed from a reference `Date` (default *today*) at **view-init** time.
///   These views re-init frequently, so a rolling window computed at init is sufficient;
///   there is deliberately no timer-based invalidation.
///
/// Each window is sized to the **widest real consumer** of the queried array in the
/// owning view (max over consumers, with margin), so bounding the query preserves the
/// existing in-view aggregates.
enum QueryWindows {

    // MARK: Window sizes

    /// Rolling window for the dashboard/goals `ActivityRecord` scans.
    ///
    /// Sized to the widest consumer across `DashboardView` / `GoalsListView` /
    /// `WorkoutAnalysisView`:
    /// - the burndown "training block" in `atRiskGoals` looks back **16 weeks**;
    /// - `BlueprintChecker` / `ProgressService` scan the current training block
    ///   (a marathon/cycling block is ≤ ~12–16 weeks);
    /// - `PeriodizationEngine` averages the last 4 weeks; `TrendWidgetView` the last 14 days.
    ///
    /// **26 weeks (~6 months)** covers all of them with margin and matches the
    /// `WorkoutSample` retention horizon (`WorkoutSampleStore.retentionMonths`).
    static let activityHistoryWeeks = 26

    /// Rolling window for `DailyReadiness` (Vibe-Score) scans. Consumers need today's
    /// record plus the 14-day trend widget; **90 days** gives ample margin. (The table
    /// holds at most one record per day, so this is a cheap, conservative bound.)
    static let readinessHistoryDays = 90

    /// Rolling window for `Symptom` scans. Every consumer reads only *today's* records
    /// (`SymptomContextFormatter.format` filters to `startOfDay`), so **30 days** is a
    /// safe, generous bound.
    static let symptomHistoryDays = 30

    // MARK: Cutoff dates

    /// Oldest `ActivityRecord.startDate` still included in the dashboard/goals scans.
    static func activityHistoryCutoff(from reference: Date = Date(),
                                      calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .weekOfYear, value: -activityHistoryWeeks, to: reference) ?? reference
    }

    /// Oldest `DailyReadiness.date` still included in the dashboard scans.
    static func readinessHistoryCutoff(from reference: Date = Date(),
                                       calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -readinessHistoryDays, to: reference) ?? reference
    }

    /// Oldest `Symptom.date` still included in the dashboard scans.
    static func symptomHistoryCutoff(from reference: Date = Date(),
                                     calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -symptomHistoryDays, to: reference) ?? reference
    }
}
