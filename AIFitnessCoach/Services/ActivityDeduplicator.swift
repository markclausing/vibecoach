import Foundation
import SwiftData

// MARK: - Epic 41: Dual-Source Single-Record-of-Truth
//
// Een Garmin-rit kan tegelijk via Apple Health (workout + HR, geen power) én via
// Strava (volledig met power) als losse `ActivityRecord` in SwiftData belanden.
// Voor de gebruiker is dat één rit; deze helper kiest de "rijkste" versie.
//
// Heuristiek-volgorde — eerste signal dat verschilt wint:
//   1. heeft samples in WorkoutSampleStore (= 5s-stream-data al ge-ingest)
//   2. `deviceWatts == true` (Strava-record gemeten met powermeter)
//   3. `trimp != nil`
//   4. `averageHeartrate != nil`
//   5. stable tiebreaker: hoogste id (lexicografisch — geeft deterministisch
//      gedrag bij volledig identieke records)
//
// Pure-Swift logica met geïnjecteerde `samplesCount`-lookup zodat de helper
// volledig unit-testbaar is zonder SwiftData / WorkoutSampleStore-afhankelijkheid.

enum ActivityDeduplicator {

    /// Tijd-tolerantie voor "dezelfde" rit: ±5 seconden op `startDate`. Garmin en
    /// Apple Watch loggen niet altijd op precies dezelfde tick.
    static let matchToleranceSeconds: TimeInterval = 5

    // MARK: Score

    /// Hogere score = rijkere versie. Pure functie — `samplesCount` injecteren maakt
    /// het testbaar zonder WorkoutSampleStore.
    static func score(record: ActivityRecord, samplesCount: Int) -> Int {
        var s = 0
        if samplesCount > 0       { s += 1000 }   // Sterkste signal
        if record.deviceWatts == true { s += 500 } // Power-meter is reeds een belofte van rijke data
        if record.trimp != nil    { s += 100 }
        if record.averageHeartrate != nil { s += 10 }
        return s
    }

    // MARK: Group

    /// Groepeert records die "dezelfde rit" representeren: zelfde sport-categorie +
    /// `startDate` binnen `matchToleranceSeconds`. Records die alleen in hun eigen
    /// groep zitten worden ook teruggegeven (size-1 groep).
    static func findDuplicateGroups(_ records: [ActivityRecord]) -> [[ActivityRecord]] {
        // Sort op startDate voor deterministische groepering.
        let sorted = records.sorted { $0.startDate < $1.startDate }
        var groups: [[ActivityRecord]] = []

        for record in sorted {
            if let lastGroup = groups.last,
               let representative = lastGroup.first,
               representative.sportCategory == record.sportCategory,
               abs(representative.startDate.timeIntervalSince(record.startDate)) <= matchToleranceSeconds {
                groups[groups.count - 1].append(record)
            } else {
                groups.append([record])
            }
        }
        return groups
    }

    // MARK: Decide

    /// Resultaat van een dedupe-analyse: wie blijft, wie wordt verwijderd.
    /// Geen `Equatable`-conformance — `ActivityRecord` is een `@Model`-class
    /// (referentie-type, niet automatisch Equatable). Tests vergelijken via `id`.
    struct Decision {
        let winners: [ActivityRecord]
        let losers: [ActivityRecord]
    }

    /// Loopt door alle groepen, kiest binnen elke groep de winnaar.
    /// - Parameters:
    ///   - records: Volledige lijst ActivityRecords (typisch alles uit de DB).
    ///   - samplesCount: Lookup-functie die per record het aantal samples teruggeeft.
    static func decide(records: [ActivityRecord],
                       samplesCount: (ActivityRecord) -> Int) -> Decision {
        let groups = findDuplicateGroups(records)
        var winners: [ActivityRecord] = []
        var losers: [ActivityRecord] = []

        for group in groups {
            guard group.count > 1 else {
                winners.append(contentsOf: group)
                continue
            }
            // Sorteer hoogste score eerst; tiebreaker op id desc (stabiel bij gelijke score).
            let ranked = group.sorted { lhs, rhs in
                let lScore = score(record: lhs, samplesCount: samplesCount(lhs))
                let rScore = score(record: rhs, samplesCount: samplesCount(rhs))
                if lScore != rScore { return lScore > rScore }
                return lhs.id > rhs.id
            }
            winners.append(ranked[0])
            losers.append(contentsOf: ranked.dropFirst())
        }
        return Decision(winners: winners, losers: losers)
    }

    // MARK: Apply (SwiftData)

    /// Voert de dedupe-actie uit op een ModelContext: verwijdert alle losers en
    /// saved. Sample-counts worden opgehaald via de meegegeven store. Idempotent —
    /// een tweede call op een schone DB doet niets.
    /// - Returns: Aantal verwijderde records.
    @MainActor
    static func runDedupe(in context: ModelContext,
                          store: WorkoutSampleStore) async throws -> Int {
        let descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        let allRecords = try context.fetch(descriptor)

        // Pre-fetch sample-counts per record (één query per record, voor 100-tal
        // records is dat acceptabel). Caching hier zou nuttig zijn bij 1000+
        // records — voor nu eenvoud boven optimalisatie.
        var counts: [String: Int] = [:]
        for record in allRecords {
            let uuid = UUID.forActivityRecordID(record.id)
            counts[record.id] = (try? await store.sampleCount(forWorkoutUUID: uuid)) ?? 0
        }

        let decision = decide(records: allRecords) { counts[$0.id] ?? 0 }

        for loser in decision.losers {
            context.delete(loser)
        }
        try context.save()
        return decision.losers.count
    }
}
