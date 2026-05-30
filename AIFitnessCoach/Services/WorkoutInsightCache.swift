import Foundation

// MARK: - Epic 32 Story 32.3b: WorkoutInsightCache
//
// Per-workout cache of the AI-generated coaching narrative. Without this cache
// the user pays a Gemini call every time they open `WorkoutAnalysisView`
// — while the patterns don't change until a reclassification
// happens. The cache key combines `activityID` + `pattern-fingerprint`
// (from `WorkoutPatternFormatter`), so invalidation happens automatically
// as soon as the detectors return a new set of patterns for the same workout.
//
// Storage: one JSON blob in `UserDefaults` under a fixed key. Deliberately not
// `@Model` — no relational queries needed, and a JSON blob is migration-free
// if we change the schema later.

struct WorkoutInsightCache {

    /// One cache entry. `Codable` so the whole dictionary can be JSON.
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

    /// Hit if: the entry exists and the fingerprint matches. On mismatch returns nil so
    /// the caller regenerates the entry and thereby overwrites the stale state automatically.
    func cached(for activityID: String, fingerprint: String) -> String? {
        let all = load()
        guard let entry = all[activityID], entry.fingerprint == fingerprint else { return nil }
        return entry.text
    }

    /// Stores or overwrites the entry for `activityID`. No TTL — the pattern
    /// fingerprint is the only invalidator.
    func store(_ text: String, for activityID: String, fingerprint: String) {
        var all = load()
        all[activityID] = Entry(text: text, fingerprint: fingerprint, generatedAt: Date())
        save(all)
    }

    /// Clears one entry. Handy when the user deliberately triggers a recalculation.
    func invalidate(activityID: String) {
        var all = load()
        all.removeValue(forKey: activityID)
        save(all)
    }

    /// Clears the whole cache. Mainly useful for tests and as a last-resort action.
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
