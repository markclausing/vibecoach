import Foundation
import SwiftData

// MARK: - Epic 41: Dual-Source Single-Record-of-Truth
//
// A Garmin ride can land in SwiftData as separate `ActivityRecord`s both via
// Apple Health (workout + HR, no power) and via Strava (fully with power).
// For the user that is one ride; this helper picks the "richest" version.
//
// Heuristic order — the first signal that differs wins:
//   1. has samples in WorkoutSampleStore (= 5s stream data already ingested)
//   2. `deviceWatts == true` (Strava record measured with a power meter)
//   3. `trimp != nil`
//   4. `averageHeartrate != nil`
//   5. stable tiebreaker: highest id (lexicographic — gives deterministic
//      behaviour for fully identical records)
//
// Pure-Swift logic with an injected `samplesCount` lookup so the helper is
// fully unit-testable without a SwiftData / WorkoutSampleStore dependency.

enum ActivityDeduplicator {

    /// Time tolerance for the "same" ride with a matching sport category. Garmin and
    /// Apple Watch don't always log on exactly the same tick.
    static let matchToleranceSeconds: TimeInterval = 5

    /// Strict tolerance for a cross-sport match. At an identical timestamp a
    /// sport-category difference is in practice a mapping issue (HK records that
    /// land in `.other` because `SportCategory.from(hkType:)` doesn't know the
    /// specific HK type id), not two workouts performed in parallel. With larger
    /// drift we do want a sport check to avoid false positives.
    static let strictMatchToleranceSeconds: TimeInterval = 1

    // MARK: Score

    /// Higher score = richer version. Pure function — injecting `samplesCount` makes
    /// it testable without WorkoutSampleStore.
    static func score(record: ActivityRecord, samplesCount: Int) -> Int {
        var s = 0
        if samplesCount > 0 { s += 1000 }   // Strongest signal
        if record.deviceWatts == true { s += 500 } // A power meter is already a promise of rich data
        if record.trimp != nil { s += 100 }
        if record.averageHeartrate != nil { s += 10 }
        return s
    }

    // MARK: Group

    /// Groups records that represent the "same ride". Two match rules:
    ///   • Strict (±1s): match regardless of sport category — catches mapping issues
    ///     (HK strength training landing as `.other` vs Strava's `.strength`)
    ///   • Loose (1-5s): requires equal sport category as a safety net against
    ///     false positives at larger timestamp drift
    /// Records that are alone in their own group are also returned.
    static func findDuplicateGroups(_ records: [ActivityRecord]) -> [[ActivityRecord]] {
        // Sort on startDate for deterministic grouping.
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

    /// Determines whether two records are the same workout based on time + sport.
    private static func isMatch(_ a: ActivityRecord, _ b: ActivityRecord) -> Bool {
        let diff = abs(a.startDate.timeIntervalSince(b.startDate))
        if diff <= strictMatchToleranceSeconds {
            // Identical second — source mapping is then unreliable, always dedupe.
            return true
        }
        if diff <= matchToleranceSeconds {
            // Drift within 5s — sport category as a safety net.
            return a.sportCategory == b.sportCategory
        }
        return false
    }

    // MARK: Decide

    /// Result of a dedupe analysis: who stays, who gets removed.
    /// No `Equatable` conformance — `ActivityRecord` is a `@Model` class
    /// (reference type, not automatically Equatable). Tests compare via `id`.
    struct Decision {
        let winners: [ActivityRecord]
        let losers: [ActivityRecord]
    }

    /// Walks through all groups and picks the winner within each group.
    /// - Parameters:
    ///   - records: Full list of ActivityRecords (typically everything from the DB).
    ///   - samplesCount: Lookup function returning the sample count per record.
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
            // Sort highest score first; tiebreaker on id desc (stable at equal score).
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

    /// Result of a `smartInsert` flow. Tests and logging callers can use this
    /// value to verify whether a record actually entered the DB, overwrote an
    /// existing one, or was deliberately discarded.
    enum SmartInsertResult: Equatable {
        case inserted
        case replaced            // new record replaced a poorer existing record
        case skippedSameSource   // exact same id already present — idempotent import
        case skippedExistingRicher // duplicate detection + existing beats new
    }

    /// Compares the richness of two records at ingest. Deliberately without a
    /// samples lookup: at ingest time the incoming record has no samples yet, so
    /// that would always set the score to 0 — inaccurate and expensive. Power
    /// meter + TRIMP + avg HR are at-the-door signals we do know.
    static func shouldReplace(existing: ActivityRecord, new: ActivityRecord) -> Bool {
        score(record: new, samplesCount: 0) > score(record: existing, samplesCount: 0)
    }

    /// Cross-source field completion (Epic #49). When dedupe picks one source as the
    /// "winner" we normally lose all of the loser's fields. For "soft" fields that
    /// have a source-independent meaning (such as ambient temperature and humidity
    /// from `HKMetadataKeyWeather*`) that's a waste — the winner often lacks those
    /// fields while the loser has them. This helper copies them over **when the
    /// winner's field is still empty**, so the final record combines the best of
    /// both sources. Called before `delete(loser)` or before discarding the
    /// candidate-that-loses.
    ///
    /// Extensible: add new "soft" fields here following the same pattern (only
    /// overwrite when the winner is nil — no assumptions about which field has
    /// the "better" value).
    static func enrichEmptyFields(into winner: ActivityRecord, from loser: ActivityRecord) {
        if winner.temperatureCelsius == nil, let temp = loser.temperatureCelsius {
            winner.temperatureCelsius = temp
        }
        if winner.humidityPercent == nil, let humidity = loser.humidityPercent {
            winner.humidityPercent = humidity
        }
    }

    /// Smart-insert pipeline for one incoming record. Follows three layers:
    ///   1. **Source-id match** → idempotent skip (re-sync of the same source).
    ///   2. **Cross-source match** within ±5s + sport category:
    ///        • new is richer → existing is removed, new is inserted.
    ///        • existing is richer (or equal) → new is skipped.
    ///   3. **No match** → regular insert.
    /// The caller must call `try context.save()` itself at a suitable moment
    /// (typically after a batch) — `smartInsert` doesn't save, to bundle N writes.
    @MainActor
    @discardableResult
    static func smartInsert(_ candidate: ActivityRecord,
                            into context: ModelContext) throws -> SmartInsertResult {
        // Layer 1 — source-id idempotency. Works for both HK UUIDs and deterministic
        // Strava ids because `ActivityRecord.id` always equals the stored source id.
        // Epic #50: the incoming candidate may have fields the existing one lacks
        // (typically weather data from Open-Meteo when re-syncing a Garmin ride).
        // Funneled through `enrichEmptyFields` before the skip — otherwise the new
        // data is lost.
        let candidateID = candidate.id
        let sameIDFetch = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.id == candidateID }
        )
        if let existingSameID = try? context.fetch(sameIDFetch),
           let existing = existingSameID.first {
            Self.enrichEmptyFields(into: existing, from: candidate)
            return .skippedSameSource
        }

        // Layer 2 — cross-source duplicate detection. The ±5s window covers both the
        // strict (1s, cross-sport) and loose (1-5s, same-sport) match rule from `findDuplicateGroups`.
        let windowStart = candidate.startDate.addingTimeInterval(-matchToleranceSeconds)
        let windowEnd   = candidate.startDate.addingTimeInterval(matchToleranceSeconds)
        let windowFetch = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.startDate >= windowStart && $0.startDate <= windowEnd }
        )
        let nearby = (try? context.fetch(windowFetch)) ?? []

        for existing in nearby {
            // Reuses `findDuplicateGroups` for one-on-one match semantics —
            // this keeps strict <1s + loose <5s+sport defined in one place.
            let groups = findDuplicateGroups([existing, candidate])
            guard groups.count == 1 else { continue }

            if shouldReplace(existing: existing, new: candidate) {
                // Epic #49: take over fields from the loser that the winner lacks —
                // this way we don't lose weather metadata from a poorer HK record if
                // the richer Strava record has no weather.
                Self.enrichEmptyFields(into: candidate, from: existing)
                context.delete(existing)
                context.insert(candidate)
                return .replaced
            } else {
                // Existing wins, but the candidate (often HK with weather metadata)
                // may have fields the existing one (often Strava without weather)
                // lacks. Carry them over before we discard the candidate.
                Self.enrichEmptyFields(into: existing, from: candidate)
                return .skippedExistingRicher
            }
        }

        // Layer 3 — no duplicate: regular insert.
        context.insert(candidate)
        return .inserted
    }

    // MARK: Apply (SwiftData)

    /// Performs the dedupe action on a ModelContext: removes all losers and saves.
    /// Sample counts are fetched via the given store. Idempotent — a second call
    /// on a clean DB does nothing.
    /// - Returns: Number of removed records.
    @MainActor
    static func runDedupe(in context: ModelContext,
                          store: WorkoutSampleStore) async throws -> Int {
        let descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        let allRecords = try context.fetch(descriptor)

        // Pre-fetch sample counts per record (one query per record, acceptable for
        // around a hundred records). Caching here would help at 1000+ records —
        // for now simplicity over optimization.
        var counts: [String: Int] = [:]
        for record in allRecords {
            let uuid = UUID.forActivityRecordID(record.id)
            counts[record.id] = (try? await store.sampleCount(forWorkoutUUID: uuid)) ?? 0
        }

        let decision = decide(records: allRecords) { counts[$0.id] ?? 0 }

        // Epic #49: cross-source field completion before delete. Carry weather
        // metadata from losers over to the winner so a Strava winner doesn't lose
        // the HK temperature. Pair losers to their winner via the same grouping
        // logic that `decide` itself uses.
        let winnersByGroup = Dictionary(uniqueKeysWithValues: decision.winners.map { ($0.id, $0) })
        let groups = findDuplicateGroups(allRecords)
        for group in groups where group.count > 1 {
            guard let winner = group.first(where: { winnersByGroup[$0.id] != nil }) else { continue }
            for loser in group where loser.id != winner.id {
                Self.enrichEmptyFields(into: winner, from: loser)
            }
        }

        for loser in decision.losers {
            context.delete(loser)
        }
        try context.save()
        return decision.losers.count
    }
}
