import Foundation
import SwiftData

// MARK: - Epic 40 Story 40.4: SessionReclassifier
//
// Na een stream-backfill (Strava 40.3 of HK DeepSync 32.1) heeft een record dat eerder
// alleen avg-HR (of niets) had ineens fijngranulaire samples. De zone-distributie-
// strategie van `SessionClassifier` (story 33.1a) levert dan een nauwkeuriger sessieType
// dan de avg-HR-fallback. Deze helper zoekt dergelijke records op en herclassificeert ze.
//
// Beschermd:
//   • `manualSessionTypeOverride == true` — gebruiker heeft zelf gekozen (zie
//     `WorkoutAnalysisView.setSessionType`); een rerun mag dat nooit overschrijven.
//   • Records zonder samples — niets te upgraden, dus geen werk te doen.
//   • Idempotent: als de classifier hetzelfde type teruggeeft als al staat, geen save.
//
// Pure-Swift `decide`-laag is volledig testbaar zonder SwiftData; `rerun` is de
// SwiftData-action wrapper, identiek patroon aan `ActivityDeduplicator.runDedupe`.

enum SessionReclassifier {

    /// Voorgestelde wijziging voor één record. `decide` produceert een lijst hiervan;
    /// `rerun` past ze toe.
    struct Change {
        let record: ActivityRecord
        let newType: SessionType
    }

    // MARK: Decide

    /// Pure-Swift kern. Loopt door records, vraagt samples op via de geïnjecteerde
    /// lookup, draait de classifier en levert alleen écht veranderende voorstellen op.
    /// - Parameters:
    ///   - records: Te overwegen records (typisch alles uit de DB).
    ///   - maxHeartRate: HRmax voor zone-berekening (Tanaka of fallback).
    ///   - samplesProvider: Lookup-functie die per record de samples teruggeeft.
    ///     Lege array = geen samples beschikbaar → record wordt overgeslagen.
    /// - Returns: Lijst voorgestelde wijzigingen. Records waarvan de classifier
    ///   `nil` of het bestaande type retourneert, zitten er niet in.
    static func decide(records: [ActivityRecord],
                       maxHeartRate: Double,
                       samplesProvider: (ActivityRecord) -> [WorkoutSample]) -> [Change] {
        // Epic #44 story 44.5: gebruik LTHR uit het profiel als die er is
        // — Friel-zones zijn preciezer voor atletische gebruikers met afwijkende
        // LTHR/max-ratio.
        let cachedLTHR = UserProfileService.cachedThreshold(forKey: UserProfileService.lactateThresholdHRKey)?.value
        let classifier = SessionClassifier(maxHeartRate: maxHeartRate, lactateThresholdHR: cachedLTHR)
        var changes: [Change] = []

        for record in records {
            // Manual override: gebruiker heeft het laatste woord — nooit overschrijven.
            if record.manualSessionTypeOverride == true { continue }

            let samples = samplesProvider(record)
            // Zonder samples valt de classifier terug op avg-HR — die had bij ingest al
            // gedraaid, dus rerun voegt niets toe. Skip om te voorkomen dat we records
            // zonder upgrade-potentieel telkens opnieuw verwerken.
            guard !samples.isEmpty else { continue }

            let suggested = classifier.classify(
                samples: samples,
                averageHeartRate: record.averageHeartrate,
                durationSeconds: record.movingTime,
                title: record.name
            )

            guard let suggested, suggested != record.sessionType else { continue }
            changes.append(Change(record: record, newType: suggested))
        }
        return changes
    }

    // MARK: Rerun (SwiftData)

    /// Voert de reclassificatie uit op een ModelContext: schrijft `sessionType` voor
    /// elke voorgestelde wijziging en saved één keer aan het einde. Idempotent —
    /// een tweede call op een al-geclassificeerde DB doet niets.
    /// - Parameters:
    ///   - context: ModelContext om uit te lezen + naar te schrijven.
    ///   - store: WorkoutSampleStore voor de samples-lookup per record.
    ///   - maxHeartRate: HRmax voor zone-berekening (Tanaka of fallback).
    /// - Returns: Aantal geherclassificeerde records.
    @MainActor
    static func rerun(in context: ModelContext,
                      store: WorkoutSampleStore,
                      maxHeartRate: Double) async throws -> Int {
        let descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        let allRecords = try context.fetch(descriptor)

        // Pre-fetch samples per record. Voor 100-tal records acceptabel; bij 1000+
        // kunnen we naar een batched-fetch toe.
        var samplesByID: [String: [WorkoutSample]] = [:]
        for record in allRecords {
            if record.manualSessionTypeOverride == true { continue }
            let uuid = UUID.forActivityRecordID(record.id)
            let samples = (try? await store.samples(forWorkoutUUID: uuid)) ?? []
            if !samples.isEmpty {
                samplesByID[record.id] = samples
            }
        }

        let changes = decide(records: allRecords, maxHeartRate: maxHeartRate) {
            samplesByID[$0.id] ?? []
        }

        for change in changes {
            change.record.sessionType = change.newType
        }
        if !changes.isEmpty {
            try context.save()
        }
        return changes.count
    }
}
