import Foundation

// MARK: - Epic 33 Story 33.4: IntentExecutionAnalyzer
//
// Compares the planned session (`SuggestedWorkout`) with the actual execution
// (`ActivityRecord`) and returns one verdict. Pure Swift — no state, no
// HealthKit dependency, fully unit-testable.
//
// Cascade order (first match wins):
//   1. typeMismatch: planned and actual SessionType known and different
//   2. overload:     TRIMP > planned + 15%
//   3. underload:    TRIMP < planned − 15%
//   4. match:        types equal + TRIMP within ±15%
//   5. insufficientData: too little signal to say anything
//
// Type mismatch outranks the TRIMP comparison because 'planned tempo, did endurance'
// is more fundamental than a TRIMP deviation — often the type difference also
// causes the TRIMP deviation, so double reporting would be noise.

/// Final verdict per (planned, actual) pair.
enum IntentExecutionVerdict: Equatable {
    case match
    case typeMismatch(planned: SessionType, actual: SessionType?)
    case overload(trimpDeltaPercent: Double)   // e.g. 22.5 for "+22.5%"
    case underload(trimpDeltaPercent: Double)  // e.g. -18.0 for "-18%"
    case insufficientData
}

enum IntentExecutionAnalyzer {

    /// TRIMP deviation margin (15% in both directions).
    private static let trimpToleranceFraction: Double = 0.15

    /// Main entry: compares the planned session against the actual execution.
    /// - Parameters:
    ///   - planned: The `SuggestedWorkout` for that day.
    ///   - actual: The `ActivityRecord` created on the same day.
    ///   - maxHeartRate: For the SessionClassifier fallback on keyword classification
    ///     of the plan. Not critical — only `classifyByKeywords` is used
    ///     and it doesn't use `maxHeartRate`, but the classifier init requires it.
    /// - Returns: An `IntentExecutionVerdict` (never `nil`; on a lack of signal
    ///   `.insufficientData`).
    static func analyze(planned: SuggestedWorkout,
                        actual: ActivityRecord,
                        maxHeartRate: Double) -> IntentExecutionVerdict {

        // Step 1 — Determine the planned SessionType via keyword classification on the
        // textual fields of the SuggestedWorkout (Option B: no schema change).
        let plannedSearchString = [planned.activityType, planned.description, planned.heartRateZone ?? ""]
            .joined(separator: " ")
        let classifier = SessionClassifier(maxHeartRate: maxHeartRate)
        let plannedType = classifier.classifyByKeywords(title: plannedSearchString)
        let actualType = actual.sessionType

        // Step 2 — Type mismatch has the highest priority.
        if let plannedType, let actualType, plannedType != actualType {
            return .typeMismatch(planned: plannedType, actual: actualType)
        }

        // Step 3 — TRIMP comparison (only if both TRIMPs are meaningful).
        guard let plannedTrimpInt = planned.targetTRIMP, plannedTrimpInt > 0 else {
            return .insufficientData
        }
        guard let actualTrimp = actual.trimp, actualTrimp > 0 else {
            return .insufficientData
        }

        let plannedTrimp = Double(plannedTrimpInt)
        let deltaFraction = (actualTrimp - plannedTrimp) / plannedTrimp
        let deltaPercent = deltaFraction * 100.0

        if deltaFraction > trimpToleranceFraction {
            return .overload(trimpDeltaPercent: deltaPercent)
        }
        if deltaFraction < -trimpToleranceFraction {
            return .underload(trimpDeltaPercent: deltaPercent)
        }

        // Step 4 — Within margin: type either equal, or one of the two unknown.
        // Both TRIMPs are within ±15% and there's no type mismatch → the coach may
        // mark this as success. An unknown type side does not weaken the signal:
        // even without an explicit type, a TRIMP match is a strong indicator of
        // discipline.
        return .match
    }
}

// MARK: - SuggestedWorkout match helper

extension Array where Element == SuggestedWorkout {
    /// Finds the `SuggestedWorkout` on the same calendar day as the given
    /// `ActivityRecord.startDate`. One-to-one: on multiple matches on one day you get
    /// the first — for 33.4 that's acceptable (a rare scenario).
    func first(matching activity: ActivityRecord) -> SuggestedWorkout? {
        let calendar = Calendar.current
        let activityDay = calendar.startOfDay(for: activity.startDate)
        return first { calendar.isDate($0.displayDate, inSameDayAs: activityDay) }
    }
}
