import Foundation
import SwiftData

/// Summary of the computed profile.
struct AthleticProfile {
    var peakDistanceInMeters: Double
    var peakDurationInSeconds: Int
    var averageWeeklyVolumeInSeconds: Int
    var daysSinceLastTraining: Int
    var isRecoveryNeeded: Bool // SPRINT 6.3 — proactive warning status
    var recoveryReason: String? // Reason for the recovery advice (which rule triggered)
    var averagePacePerKmInSeconds: Int? // SPRINT 9.3 — average running pace
}

/// Responsible for computing the athletic profile from historical data in SwiftData.
@MainActor
class AthleticProfileManager {

    // Epic 39 Story 39.1: the logger now lives in `AppLoggers` — main-actor isolation
    // on a `static let` caused 70 Swift 6 warnings from @Sendable
    // HealthKit callbacks.

    /// Computes the profile from the available `ActivityRecord` elements.
    /// Includes the overtraining logic (Sprint 6.3).
    /// - Parameter context: The app's `ModelContext` to read data from.
    /// - Returns: A computed `AthleticProfile`, or nil if there is insufficient data.
    func calculateProfile(context: ModelContext) throws -> AthleticProfile? {
        let fetchDescriptor = FetchDescriptor<ActivityRecord>()
        let allActivities = try context.fetch(fetchDescriptor)

        guard !allActivities.isEmpty else {
            return nil
        }

        // 1. Peak performance
        let peakDistance = allActivities.max(by: { $0.distance < $1.distance })?.distance ?? 0.0
        let peakDuration = allActivities.max(by: { $0.movingTime < $1.movingTime })?.movingTime ?? 0

        // 2. Days since the last training
        let mostRecentActivity = allActivities.max(by: { $0.startDate < $1.startDate })
        let daysSinceLast: Int
        if let recentActivity = mostRecentActivity {
            let components = Calendar.current.dateComponents([.day], from: recentActivity.startDate, to: Date())
            daysSinceLast = components.day ?? 0
        } else {
            daysSinceLast = 0
        }

        // 3. Weekly average volume over the past 4 weeks
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

        // 4. SPRINT 6.3: overtraining logic
        var needsRecovery = false
        var recoveryReason: String?

        // Compute the volume of *only* the past week
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

        // Rule 1: this week's volume is > 50% higher than the average
        if averageWeeklyVolume > 7200 {
            let ratio = Double(thisWeekVolume) / Double(averageWeeklyVolume)
            if ratio > 1.5 {
                needsRecovery = true
                let pct = Int((ratio - 1.0) * 100)
                recoveryReason = "Volume deze week is \(pct)% boven je gemiddelde. Plan 1–2 rustdagen."
            }
        }

        // Rule 2: trained 4 or more days in a row
        guard let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance, peakDurationInSeconds: peakDuration, averageWeeklyVolumeInSeconds: averageWeeklyVolume, daysSinceLastTraining: max(0, daysSinceLast), isRecoveryNeeded: needsRecovery, recoveryReason: recoveryReason, averagePacePerKmInSeconds: nil)
        }
        let daysTrainedInLast4Days = Set(thisWeekActivities.filter { $0.startDate >= fourDaysAgo }.map { Calendar.current.startOfDay(for: $0.startDate) }).count

        if daysTrainedInLast4Days >= 4 {
            needsRecovery = true
            recoveryReason = "\(daysTrainedInLast4Days) dagen op rij getraind. Neem vandaag rust."
        }

        // 5. SPRINT 9.3: compute average pace (baseline pace)
        var averagePace: Int?
        if let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            let runningActivities = allActivities.filter {
                $0.startDate >= thirtyDaysAgo && $0.sportCategory == .running
            }

            let totalRunningDistance = runningActivities.reduce(0.0) { $0 + $1.distance }
            let totalRunningTime = runningActivities.reduce(0) { $0 + $1.movingTime }

            // Guard against division by zero and ensure reliable data (at least 1km run)
            if totalRunningDistance > 1000.0 && totalRunningTime > 0 {
                // Pace = (time in seconds / distance in metres) * 1000 = seconds per kilometre
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
