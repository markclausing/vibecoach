import HealthKit

// MARK: - Epic 38 Story 38.2: HealthKit-sync-status-evaluator
//
// Pure-Swift beslissingslogica voor de "stille sync"-banner op het Dashboard.
// Door de regel als testbare static functie te isoleren, hoeven we geen
// `HKHealthStore`-mock te bouwen om te valideren wanneer de banner verschijnt
// — caller geeft de twee inputs door en krijgt een Bool terug. Geen UI-,
// AppStorage- of HealthKit-query-afhankelijkheid.
//
// Strikte conditie (38.2): banner alleen wanneer er 0 workouts in het 365d-
// venster zijn EN het workout-type niet expliciet `.sharingAuthorized` heeft.
// Gedeeltelijke toestemming (workouts wel, hartslag niet) is bewust buiten
// scope — die degraderen vanzelf zichtbaar in lege HR-grafieken (Epic 32/40).
// Een aparte banner per ontbrekend type zou het dashboard te druk maken.

enum HealthKitSyncStatusEvaluator {

    /// Returns `true` wanneer we de "controleer toestemmingen"-banner moeten
    /// tonen. Logica: 0 workouts in venster én workout-auth-status niet
    /// `sharingAuthorized` (dus `denied` of `notDetermined`).
    /// - Parameters:
    ///   - workoutCount: aantal workouts dat de laatste sync uit HK terugkreeg
    ///     in het 365d-window (cached via AppStorage door `AppTabHostView`).
    ///   - workoutAuthStatus: `HKHealthStore.authorizationStatus(for:)` op
    ///     `HKObjectType.workoutType()` op het moment van banner-render.
    static func shouldWarn(workoutCount: Int,
                           workoutAuthStatus: HKAuthorizationStatus) -> Bool {
        workoutCount == 0 && workoutAuthStatus != .sharingAuthorized
    }
}
