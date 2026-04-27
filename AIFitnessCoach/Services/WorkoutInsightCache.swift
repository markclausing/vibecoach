import Foundation

// MARK: - Epic 32 Story 32.3b: WorkoutInsightCache
//
// Per-workout cache van de AI-gegenereerde coaching-narrative. Zonder deze cache
// betaalt de gebruiker een Gemini-call elke keer dat ze `WorkoutAnalysisView`
// openen — terwijl de patronen niet veranderen tot er een re-classificatie
// plaatsvindt. Cache-key combineert `activityID` + `pattern-fingerprint`
// (uit `WorkoutPatternFormatter`), zodat invalidatie automatisch gebeurt
// zodra detectoren een nieuwe set patronen retourneren voor dezelfde workout.
//
// Storage: één JSON-blob in `UserDefaults` onder een vaste key. Bewust geen
// `@Model` — geen relationele queries nodig, en JSON-blob is migratie-vrij
// als we het schema later aanpassen.

struct WorkoutInsightCache {

    /// Eén cache-entry. `Codable` zodat de hele dictionary in JSON kan.
    struct Entry: Codable, Equatable {
        let text: String
        let fingerprint: String
        let generatedAt: Date
    }

    private static let storageKey = "WorkoutInsightCache.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Hit als: entry bestaat én fingerprint matcht. Bij mismatch returnt nil zodat
    /// caller de entry vers genereert en daarmee de stale-state automatisch overschrijft.
    func cached(for activityID: String, fingerprint: String) -> String? {
        let all = load()
        guard let entry = all[activityID], entry.fingerprint == fingerprint else { return nil }
        return entry.text
    }

    /// Bewaart of overschrijft de entry voor `activityID`. Geen TTL — pattern-
    /// fingerprint is de enige invalidator.
    func store(_ text: String, for activityID: String, fingerprint: String) {
        var all = load()
        all[activityID] = Entry(text: text, fingerprint: fingerprint, generatedAt: Date())
        save(all)
    }

    /// Wist één entry. Handig wanneer de gebruiker bewust een herberekening triggert.
    func invalidate(activityID: String) {
        var all = load()
        all.removeValue(forKey: activityID)
        save(all)
    }

    /// Wist de hele cache. Vooral nuttig voor tests en als laatste-redmiddel-actie.
    func clearAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: Storage

    private func load() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
