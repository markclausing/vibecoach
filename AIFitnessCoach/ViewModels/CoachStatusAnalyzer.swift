import Foundation

/// Story 65.3: data-source orchestration for the "analyse current status" flow.
///
/// Extracted from `ChatViewModel` — the HealthKit-first / Strava-fallback / reverse-fallback
/// logic and the `DailyWorkout` mapping now live here. Returns a pure `Outcome` (workouts or
/// a user-facing message); the view model owns the resulting UI (prompt build + chat message).
///
/// `@MainActor` because it is driven from the `@MainActor` `ChatViewModel` and awaits the
/// shared HealthKit/Strava services.
@MainActor
final class CoachStatusAnalyzer {

    /// The result of a status fetch: mapped workout days, or a localized message to show.
    enum Outcome {
        case workouts([CoachPromptAssembler.DailyWorkout])
        case message(String)
    }

    private let fitnessDataService: FitnessDataService
    private let healthKitManager: HealthKitManager
    private let fitnessCalculator: PhysiologicalCalculatorProtocol

    init(fitnessDataService: FitnessDataService,
         healthKitManager: HealthKitManager,
         fitnessCalculator: PhysiologicalCalculatorProtocol) {
        self.fitnessDataService = fitnessDataService
        self.healthKitManager = healthKitManager
        self.fitnessCalculator = fitnessCalculator
    }

    /// Fetches recent workouts for the past `days` via the selected `source`, applying the
    /// same fallback waterfall as before: HealthKit source → Strava on empty/error;
    /// Strava source → reverse-fallback to HealthKit on empty/error.
    func fetchRecentWorkouts(days: Int, source: DataSource) async -> Outcome {
        if source == .healthKit {
            do {
                let workouts = try await healthKitManager.fetchRecentWorkouts(days: days)
                if !workouts.isEmpty {
                    return .workouts(map(healthKitWorkouts: workouts))
                }
                AppLoggers.coach.notice("No or empty HealthKit workouts found, falling back to Strava.")
            } catch {
                AppLoggers.coach.warning("Error fetching HealthKit data (\(error.localizedDescription, privacy: .public)), falling back to Strava.")
            }
            // HK empty/error → try Strava as the source's own path (no reverse — source is HK).
            return await fetchStrava(days: days, source: source)
        } else {
            return await fetchStrava(days: days, source: source)
        }
    }

    // MARK: - Strava

    private func fetchStrava(days: Int, source: DataSource) async -> Outcome {
        do {
            let activities = try await fitnessDataService.fetchRecentActivities(days: days)

            if activities.isEmpty {
                if source == .strava {
                    // Reverse fallback: Strava empty and Strava was the source → try HealthKit.
                    AppLoggers.coach.notice("No recent Strava activity found. Reverse fallback to HealthKit.")
                    return await reverseHealthKit(days: days)
                }
                return .message(String(localized: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
            }
            return .workouts(map(stravaActivities: activities))

        } catch let error as FitnessDataError {
            if source == .strava {
                AppLoggers.coach.warning("Strava API error (\(error.localizedDescription, privacy: .public)). Reverse fallback to HealthKit.")
                return await reverseHealthKit(days: days)
            }
            return .message(stravaErrorMessage(error))
        } catch {
            if source == .strava {
                return await reverseHealthKit(days: days)
            }
            return .message("Er is een onbekende fout opgetreden.")
        }
    }

    /// Reverse fallback to HealthKit after Strava fails (the terminal branch — no further fallback).
    private func reverseHealthKit(days: Int) async -> Outcome {
        do {
            let workouts = try await healthKitManager.fetchRecentWorkouts(days: days)
            if !workouts.isEmpty {
                return .workouts(map(healthKitWorkouts: workouts))
            }
            return .message(String(localized: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
        } catch {
            return .message(String(localized: "Ik kon geen recente trainingen vinden. HealthKit fout: \(error.localizedDescription)"))
        }
    }

    private func stravaErrorMessage(_ error: FitnessDataError) -> String {
        var errorMsg = String(localized: "Fout bij ophalen van data: ")
        switch error {
        case .missingToken: errorMsg += String(localized: "Je bent niet ingelogd op Strava. Ga naar instellingen om te koppelen.")
        case .unauthorized: errorMsg += String(localized: "Je Strava sessie is verlopen. Koppel opnieuw in de instellingen.")
        case .rateLimited(let retryAfter):
            let f = AppDateFormatters.display("HH:mm")
            errorMsg += String(localized: "Strava-limiet bereikt — hervat om \(f.string(from: retryAfter)).")
        case .networkError(let desc): errorMsg += String(localized: "Netwerkfout (\(desc)).")
        case .decodingError(let desc): errorMsg += String(localized: "Data onleesbaar (\(desc)).")
        case .invalidResponse: errorMsg += String(localized: "Ongeldig antwoord van de server.")
        }
        return errorMsg
    }

    // MARK: - Mapping

    private func map(healthKitWorkouts workouts: [WorkoutDetails]) -> [CoachPromptAssembler.DailyWorkout] {
        workouts.map { workout in
            let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: workout.averageHeartRate, maxHeartRate: workout.maxHeartRate, restingHeartRate: workout.restingHeartRate)
            return CoachPromptAssembler.DailyWorkout(date: workout.startDate, name: workout.name, durationMinutes: Int(workout.duration / 60.0), trimp: Int(calculatedTSS))
        }
    }

    private func map(stravaActivities activities: [StravaActivity]) -> [CoachPromptAssembler.DailyWorkout] {
        let formatter = ISO8601DateFormatter()
        return activities.map { activity in
            let date = formatter.date(from: activity.start_date) ?? Date()
            // Estimate resting/max HR when Strava doesn't provide them.
            let avgHR = activity.average_heartrate ?? 140.0
            let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: Double(activity.moving_time), averageHeartRate: avgHR, maxHeartRate: 190.0, restingHeartRate: 60.0)
            return CoachPromptAssembler.DailyWorkout(date: date, name: activity.name, durationMinutes: activity.moving_time / 60, trimp: Int(calculatedTSS))
        }
    }
}
