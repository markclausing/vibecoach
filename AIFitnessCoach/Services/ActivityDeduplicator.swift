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

    /// Tijd-tolerantie voor "dezelfde" rit met matching sport-categorie. Garmin en
    /// Apple Watch loggen niet altijd op precies dezelfde tick.
    static let matchToleranceSeconds: TimeInterval = 5

    /// Strikte tolerantie voor cross-sport-match. Bij identieke timestamp is een
    /// sport-categorie-verschil in de praktijk een mapping-issue (HK-records die
    /// in `.other` belanden omdat `SportCategory.from(hkType:)` de specifieke
    /// HK-type-id niet kent), niet twee parallel uitgevoerde workouts. Bij grotere
    /// drift willen we wel een sport-check om false positives te vermijden.
    static let strictMatchToleranceSeconds: TimeInterval = 1

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

    /// Groepeert records die "dezelfde rit" representeren. Twee match-regels:
    ///   • Strict (±1s): match ongeacht sport-categorie — vangt mapping-issues op
    ///     (HK krachttraining die als `.other` belandt vs Strava's `.strength`)
    ///   • Loose (1-5s): vereist gelijke sport-categorie als veiligheidsnet tegen
    ///     false positives bij grotere timestamp-drift
    /// Records die alleen in hun eigen groep zitten worden ook teruggegeven.
    static func findDuplicateGroups(_ records: [ActivityRecord]) -> [[ActivityRecord]] {
        // Sort op startDate voor deterministische groepering.
        let sorted = records.sorted { $0.startDate < $1.startDate }
        var groups: [[ActivityRecord]] = []

        for record in sorted {
            if let lastGroup = groups.last,
               let representative = lastGroup.first,
               isMatch(representative, record) {
                groups[groups.count - 1].append(record)
            } else {
                groups.append([record])
            }
        }
        return groups
    }

    /// Bepaalt of twee records dezelfde workout zijn op basis van time + sport.
    private static func isMatch(_ a: ActivityRecord, _ b: ActivityRecord) -> Bool {
        let diff = abs(a.startDate.timeIntervalSince(b.startDate))
        if diff <= strictMatchToleranceSeconds {
            // Identieke seconde — bron-mapping is dan onbetrouwbaar, dedupe altijd.
            return true
        }
        if diff <= matchToleranceSeconds {
            // Drift binnen 5s — sport-categorie als veiligheidsnet.
            return a.sportCategory == b.sportCategory
        }
        return false
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

    // MARK: Smart Ingest (Epic 41.4)

    /// Resultaat van een `smartInsert`-flow. Tests en logging-callers kunnen op
    /// basis van deze waarde verifiëren of een record daadwerkelijk de DB inging,
    /// een bestaande overschreef of bewust werd weggegooid.
    enum SmartInsertResult: Equatable {
        case inserted
        case replaced            // new record verving een armer existing-record
        case skippedSameSource   // exact dezelfde id stond er al — idempotente import
        case skippedExistingRicher // duplicaat-detectie + existing wint van new
    }

    /// Vergelijkt rijkdom van twee records bij ingest. Bewust zonder samples-lookup:
    /// op het ingest-moment zijn er voor de incoming record nog geen samples binnen,
    /// dus die zouden de score altijd op 0 zetten — onnauwkeurig én duur. Power-meter
    /// + TRIMP + avg-HR zijn aan-de-deur signalen die we wél kennen.
    static func shouldReplace(existing: ActivityRecord, new: ActivityRecord) -> Bool {
        score(record: new, samplesCount: 0) > score(record: existing, samplesCount: 0)
    }

    /// Smart-insert pipeline voor één incoming record. Volgt drie lagen:
    ///   1. **Source-id match** → idempotente skip (re-sync van dezelfde bron).
    ///   2. **Cross-source match** binnen ±5s + sport-categorie:
    ///        • new is rijker → existing wordt verwijderd, new geïnsert.
    ///        • existing is rijker (of gelijk) → new wordt overgeslagen.
    ///   3. **Geen match** → reguliere insert.
    /// Caller moet zélf `try context.save()` aanroepen op een geschikt moment
    /// (typisch na een batch) — `smartInsert` saved niet om N writes te bundelen.
    @MainActor
    @discardableResult
    static func smartInsert(_ candidate: ActivityRecord,
                            into context: ModelContext) throws -> SmartInsertResult {
        // Laag 1 — source-id idempotency. Werkt voor zowel HK-UUID's als deterministische
        // Strava-id's omdat `ActivityRecord.id` altijd gelijk is aan de stored source-id.
        let candidateID = candidate.id
        let sameIDFetch = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.id == candidateID }
        )
        if let existingSameID = try? context.fetch(sameIDFetch), !existingSameID.isEmpty {
            return .skippedSameSource
        }

        // Laag 2 — cross-source duplicaat-detectie. ±5s window vangt zowel de strict
        // (1s, cross-sport) als de loose (1-5s, same-sport) match-regel uit `findDuplicateGroups`.
        let windowStart = candidate.startDate.addingTimeInterval(-matchToleranceSeconds)
        let windowEnd   = candidate.startDate.addingTimeInterval(matchToleranceSeconds)
        let windowFetch = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.startDate >= windowStart && $0.startDate <= windowEnd }
        )
        let nearby = (try? context.fetch(windowFetch)) ?? []

        for existing in nearby {
            // Hergebruikt `findDuplicateGroups` voor één-op-één match-semantics —
            // zo blijft strict <1s + loose <5s+sport in één plek gedefinieerd.
            let groups = findDuplicateGroups([existing, candidate])
            guard groups.count == 1 else { continue }

            if shouldReplace(existing: existing, new: candidate) {
                context.delete(existing)
                context.insert(candidate)
                return .replaced
            } else {
                return .skippedExistingRicher
            }
        }

        // Laag 3 — geen duplicaat: reguliere insert.
        context.insert(candidate)
        return .inserted
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
