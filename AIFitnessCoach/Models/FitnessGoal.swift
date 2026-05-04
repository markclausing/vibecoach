import Foundation
import SwiftData

// MARK: - Epic Doel-Intenties: Enums

/// Het formaat van het evenement waarvoor de gebruiker traint.
enum EventFormat: String, Codable, CaseIterable {
    case singleDayRace  = "single_day_race"
    case singleDayTour  = "single_day_tour"
    case multiDayStage  = "multi_day_stage"

    var displayName: String {
        switch self {
        case .singleDayRace:  return "Eendaagse wedstrijd"
        case .singleDayTour:  return "Eendaagse toertocht"
        case .multiDayStage:  return "Meerdaagse etapperit"
        }
    }
}

/// De primaire intentie van de gebruiker voor het evenement.
enum PrimaryIntent: String, Codable, CaseIterable {
    case completion      = "completion"
    case peakPerformance = "peak_performance"

    var displayName: String {
        switch self {
        case .completion:      return "Uitlopen / overleven"
        case .peakPerformance: return "Zo snel mogelijk"
        }
    }
}

/// Represents a user's fitness goal.
/// Dit model wordt opgeslagen in SwiftData om lokale doelen bij te houden.
@Model
final class FitnessGoal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String?
    var targetDate: Date
    var createdAt: Date
    var isCompleted: Bool
    var sportCategory: SportCategory?
    var targetTRIMP: Double? // Sprint 12.1: Benodigde belasting om dit doel te halen.

    // Epic Doel-Intenties — Optionals zodat SwiftData oude records veilig als nil inlaadt
    var format: EventFormat?
    var intent: PrimaryIntent?
    var stretchGoalTime: TimeInterval?

    /// Veilige fallback: geeft altijd een geldige EventFormat terug, ook voor records zonder waarde.
    var resolvedFormat: EventFormat { format ?? .singleDayRace }

    /// Veilige fallback: geeft altijd een geldige PrimaryIntent terug, ook voor records zonder waarde.
    var resolvedIntent: PrimaryIntent { intent ?? .peakPerformance }

    init(id: UUID = UUID(),
         title: String,
         details: String? = nil,
         targetDate: Date,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         sportCategory: SportCategory? = nil,
         targetTRIMP: Double? = nil,
         format: EventFormat? = .singleDayRace,
         intent: PrimaryIntent? = .peakPerformance,
         stretchGoalTime: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.sportCategory = sportCategory
        self.targetTRIMP = targetTRIMP
        self.format = format
        self.intent = intent
        self.stretchGoalTime = stretchGoalTime
    }

    /// Huidige trainingsfase van dit doel op basis van weken resterend (Epic 16).
    /// Retourneert nil als het doel is afgerond of al verlopen.
    var currentPhase: TrainingPhase? {
        guard !isCompleted, Date() < targetDate else { return nil }
        return TrainingPhase.calculate(weeksRemaining: weeksRemaining)
    }

    /// Berekent of retourneert de Target TRIMP veilig, inclusief fail-safe fallback formule
    var computedTargetTRIMP: Double {
        if let trimp = targetTRIMP, trimp > 0 {
            return trimp
        }
        let days = max(1.0, totalDays)
        return (days / 7.0) * 350.0
    }

    // MARK: - DST-veilige tijdberekeningen (CLAUDE.md §3)

    /// Aantal weken tot `targetDate` op het opgegeven moment — DST-veilig.
    /// Negatief als het doel al verlopen is. Standaard t.o.v. `Date()`.
    func weeksRemaining(from now: Date = Date()) -> Double {
        Calendar.current.fractionalWeeks(from: now, to: targetDate)
    }

    /// Aantal weken tot `targetDate` t.o.v. nu (computed-property accessor voor `weeksRemaining(from:)`).
    var weeksRemaining: Double { weeksRemaining() }

    /// Aantal dagen tot `targetDate` op het opgegeven moment — DST-veilig.
    /// Negatief als het doel al verlopen is.
    func daysRemaining(from now: Date = Date()) -> Double {
        Calendar.current.fractionalDays(from: now, to: targetDate)
    }

    /// Aantal dagen tot `targetDate` t.o.v. nu (fractioneel, DST-veilig).
    var daysRemaining: Double { daysRemaining() }

    /// Totaal aantal dagen tussen `createdAt` en `targetDate` — DST-veilig.
    /// Gebruikt voor totaal-trainingsperiode-berekeningen (zoals fallback Target TRIMP).
    var totalDays: Double {
        Calendar.current.fractionalDays(from: createdAt, to: targetDate)
    }
}
