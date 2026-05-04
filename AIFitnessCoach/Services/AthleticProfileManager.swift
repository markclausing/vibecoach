import Foundation
import SwiftData

/// Samenvatting van het berekende profiel
struct AthleticProfile {
    var peakDistanceInMeters: Double
    var peakDurationInSeconds: Int
    var averageWeeklyVolumeInSeconds: Int
    var daysSinceLastTraining: Int
    var isRecoveryNeeded: Bool // SPRINT 6.3 - Proactieve Waarschuwing status
    var recoveryReason: String? // Reden voor het hersteladvies (welke regel heeft getriggerd)
    var averagePacePerKmInSeconds: Int? // SPRINT 9.3 - Gemiddeld hardlooptempo
}

/// Verantwoordelijk voor het berekenen van het atleetprofiel op basis van historische gegevens in SwiftData.
@MainActor
class AthleticProfileManager {

    // Epic 39 Story 39.1: logger leeft nu in `AppLoggers` — main-actor-isolation
    // op een `static let` veroorzaakte 70 Swift 6-warnings vanuit @Sendable
    // HealthKit-callbacks.

    /// Berekent het profiel op basis van de aanwezige `ActivityRecord` elementen.
    /// Inclusief de Overtraining logica (Sprint 6.3).
    /// - Parameter context: De `ModelContext` van de app om gegevens uit te lezen.
    /// - Returns: Een berekend `AthleticProfile` of nil als er onvoldoende data is.
    func calculateProfile(context: ModelContext) throws -> AthleticProfile? {
        let fetchDescriptor = FetchDescriptor<ActivityRecord>()
        let allActivities = try context.fetch(fetchDescriptor)

        guard !allActivities.isEmpty else {
            return nil
        }

        // 1. Piekprestatie
        let peakDistance = allActivities.max(by: { $0.distance < $1.distance })?.distance ?? 0.0
        let peakDuration = allActivities.max(by: { $0.movingTime < $1.movingTime })?.movingTime ?? 0

        // 2. Dagen sinds de laatste training
        let mostRecentActivity = allActivities.max(by: { $0.startDate < $1.startDate })
        let daysSinceLast: Int
        if let recentActivity = mostRecentActivity {
            let components = Calendar.current.dateComponents([.day], from: recentActivity.startDate, to: Date())
            daysSinceLast = components.day ?? 0
        } else {
            daysSinceLast = 0
        }

        // 3. Wekelijks gemiddeld volume van de afgelopen 4 weken
        let now = Date()
        guard let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance,
                                   peakDurationInSeconds: peakDuration,
                                   averageWeeklyVolumeInSeconds: 0,
                                   daysSinceLastTraining: daysSinceLast,
                                   isRecoveryNeeded: false,
                                   recoveryReason: nil,
                                   averagePacePerKmInSeconds: nil)
        }

        let recentActivities = allActivities.filter { $0.startDate >= fourWeeksAgo }
        let totalVolumeRecent = recentActivities.reduce(0) { $0 + $1.movingTime }
        let averageWeeklyVolume = totalVolumeRecent / 4

        // 4. SPRINT 6.3: Overtrainingslogica
        var needsRecovery = false
        var recoveryReason: String? = nil

        // Bereken volume van *alleen* de afgelopen week
        guard let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance,
                                   peakDurationInSeconds: peakDuration,
                                   averageWeeklyVolumeInSeconds: averageWeeklyVolume,
                                   daysSinceLastTraining: daysSinceLast,
                                   isRecoveryNeeded: false,
                                   recoveryReason: nil,
                                   averagePacePerKmInSeconds: nil)
        }
        let thisWeekActivities = recentActivities.filter { $0.startDate >= oneWeekAgo }
        let thisWeekVolume = thisWeekActivities.reduce(0) { $0 + $1.movingTime }

        // Regel 1: Volume deze week is > 50% hoger dan het gemiddelde
        if averageWeeklyVolume > 7200 {
            let ratio = Double(thisWeekVolume) / Double(averageWeeklyVolume)
            if ratio > 1.5 {
                needsRecovery = true
                let pct = Int((ratio - 1.0) * 100)
                recoveryReason = "Volume deze week is \(pct)% boven je gemiddelde. Plan 1–2 rustdagen."
            }
        }

        // Regel 2: Traint al 4 of meer dagen op rij
        guard let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance, peakDurationInSeconds: peakDuration, averageWeeklyVolumeInSeconds: averageWeeklyVolume, daysSinceLastTraining: max(0, daysSinceLast), isRecoveryNeeded: needsRecovery, recoveryReason: recoveryReason, averagePacePerKmInSeconds: nil)
        }
        let daysTrainedInLast4Days = Set(thisWeekActivities.filter { $0.startDate >= fourDaysAgo }.map { Calendar.current.startOfDay(for: $0.startDate) }).count

        if daysTrainedInLast4Days >= 4 {
            needsRecovery = true
            recoveryReason = "\(daysTrainedInLast4Days) dagen op rij getraind. Neem vandaag rust."
        }

        // 5. SPRINT 9.3: Gemiddeld tempo berekenen (baseline pace)
        var averagePace: Int? = nil
        if let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            let runningActivities = allActivities.filter {
                $0.startDate >= thirtyDaysAgo && $0.sportCategory == .running
            }

            let totalRunningDistance = runningActivities.reduce(0.0) { $0 + $1.distance }
            let totalRunningTime = runningActivities.reduce(0) { $0 + $1.movingTime }

            // Controleer op division by zero en zorg voor betrouwbare data (minimaal 1km gelopen)
            if totalRunningDistance > 1000.0 && totalRunningTime > 0 {
                // Pace = (tijd in seconden / afstand in meters) * 1000 = seconden per kilometer
                averagePace = Int((Double(totalRunningTime) / totalRunningDistance) * 1000.0)
            }
        }

        return AthleticProfile(
            peakDistanceInMeters: peakDistance,
            peakDurationInSeconds: peakDuration,
            averageWeeklyVolumeInSeconds: averageWeeklyVolume,
            daysSinceLastTraining: max(0, daysSinceLast),
            isRecoveryNeeded: needsRecovery,
            recoveryReason: recoveryReason,
            averagePacePerKmInSeconds: averagePace
        )
    }
}
