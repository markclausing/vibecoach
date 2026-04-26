import Foundation

// MARK: - Epic 33 Story 33.4: IntentExecutionAnalyzer
//
// Vergelijkt de geplande sessie (`SuggestedWorkout`) met de werkelijke uitvoering
// (`ActivityRecord`) en geeft één verdict terug. Pure Swift — geen state, geen
// HealthKit-dependency, volledig unit-testbaar.
//
// Cascade-volgorde (eerste match wint):
//   1. typeMismatch: planned- en actual-SessionType bekend én verschillend
//   2. overload:     TRIMP > planned + 15%
//   3. underload:    TRIMP < planned − 15%
//   4. match:        types gelijk + TRIMP binnen ±15%
//   5. insufficientData: te weinig signaal om iets te zeggen
//
// Type-mismatch gaat boven TRIMP-vergelijking omdat 'gepland tempo, gedaan endurance'
// fundamenteler is dan een TRIMP-afwijking — vaak veroorzaakt het type-verschil
// óók de TRIMP-afwijking, dus dubbele rapportage zou ruis zijn.

/// Eindoordeel per (planned, actual)-paar.
enum IntentExecutionVerdict: Equatable {
    case match
    case typeMismatch(planned: SessionType, actual: SessionType?)
    case overload(trimpDeltaPercent: Double)   // bv. 22.5 voor "+22.5%"
    case underload(trimpDeltaPercent: Double)  // bv. -18.0 voor "-18%"
    case insufficientData
}

enum IntentExecutionAnalyzer {

    /// TRIMP-afwijking-marge (15% in beide richtingen).
    private static let trimpToleranceFraction: Double = 0.15

    /// Hoofd-entry: vergelijkt geplande sessie tegen werkelijke uitvoering.
    /// - Parameters:
    ///   - planned: De `SuggestedWorkout` voor de betreffende dag.
    ///   - actual: De `ActivityRecord` die op dezelfde dag is gemaakt.
    ///   - maxHeartRate: Voor de SessionClassifier-fallback bij keyword-classificatie
    ///     van het plan. Niet kritiek — alleen `classifyByKeywords` wordt gebruikt
    ///     en die gebruikt `maxHeartRate` niet, maar de classifier-init eist 'm.
    /// - Returns: Een `IntentExecutionVerdict` (nooit `nil`; bij gebrek aan signaal
    ///   `.insufficientData`).
    static func analyze(planned: SuggestedWorkout,
                        actual: ActivityRecord,
                        maxHeartRate: Double) -> IntentExecutionVerdict {

        // Stap 1 — Bepaal het geplande SessionType via keyword-classificatie op de
        // tekstuele velden van de SuggestedWorkout (Optie B: geen schema-wijziging).
        let plannedSearchString = [planned.activityType, planned.description, planned.heartRateZone ?? ""]
            .joined(separator: " ")
        let classifier = SessionClassifier(maxHeartRate: maxHeartRate)
        let plannedType = classifier.classifyByKeywords(title: plannedSearchString)
        let actualType = actual.sessionType

        // Stap 2 — Type-mismatch heeft hoogste prioriteit.
        if let plannedType, let actualType, plannedType != actualType {
            return .typeMismatch(planned: plannedType, actual: actualType)
        }

        // Stap 3 — TRIMP-vergelijking (alleen als beide TRIMPs zinvol zijn).
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

        // Stap 4 — Binnen marge: type ofwel gelijk, ofwel één van beide onbekend.
        // Beide TRIMPs zijn binnen ±15% en geen type-mismatch → coach mag dit als
        // success markeren. Een onbekende type-zijde verzwakt het signaal niet:
        // zelfs zonder explicit type is een TRIMP-match een sterk indicator van
        // discipline.
        return .match
    }
}

// MARK: - SuggestedWorkout match-helper

extension Array where Element == SuggestedWorkout {
    /// Vindt de `SuggestedWorkout` die op dezelfde kalenderdag staat als de gegeven
    /// `ActivityRecord.startDate`. Eén-op-één: bij meerdere matches op één dag krijg
    /// je de eerste — voor 33.4 is dat acceptabel (zeldzaam scenario).
    func first(matching activity: ActivityRecord) -> SuggestedWorkout? {
        let calendar = Calendar.current
        let activityDay = calendar.startOfDay(for: activity.startDate)
        return first { calendar.isDate($0.displayDate, inSameDayAs: activityDay) }
    }
}
