import Foundation

// MARK: - Epic #51-F4: Weer-fout retry-marker
//
// Open-Meteo-fouten (timeout, captive-portal, 5xx) zijn niet kritisch — de
// weer-data is *verrijking*, niet kern. Maar een gemiste enrichment moet
// later opnieuw worden geprobeerd zodat een ritje uit een hotel-Wi-Fi
// achteraf alsnog wordt aangevuld zodra er gewone verbinding is.
//
// We slaan een retry-marker op buiten SwiftData (UserDefaults-dict) zodat
// een nieuw veld op `ActivityRecord` geen schema-migratie vereist
// (CLAUDE.md §2.1 dwingt een SchemaV<N+1> + MigrationStage af voor élke
// `@Model`-wijziging, zelfs pure additions — niet de moeite waard voor
// een hint-veld dat lokaal blijft en hooguit per app-reinstall verloren
// gaat — bij reinstall is alle data sowieso ververst).
//
// Structuur: `[activityID: failedAtUnixTimestamp]`. Backoff-logica zit
// in `WeatherEnrichmentRetryRunner` (de orchestrator), niet in de store —
// de store is dom.

struct WeatherRetryStore {
    static let key = "vibecoach_weatherFetchFailures"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Markeer een activity-ID als "weer-fetch gefaald op `at`".
    func markFailed(activityID: String, at date: Date = Date()) {
        var map = readMap()
        map[activityID] = date.timeIntervalSince1970
        write(map)
    }

    /// Wis de marker — gebruikt door een succesvolle retry zodat we niet
    /// eeuwig blijven retryen op een al-aangevulde activity.
    func clear(activityID: String) {
        var map = readMap()
        if map.removeValue(forKey: activityID) != nil {
            write(map)
        }
    }

    /// Tijdstip van de laatste failure, of `nil` als er geen marker hangt.
    func failedSince(activityID: String) -> Date? {
        guard let value = readMap()[activityID] else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// IDs die "klaar zijn voor een retry" — geen recente failure-marker
    /// (of marker ouder dan `cooldown`), zodat we Open-Meteo niet platleggen
    /// met een retry-storm bij een persistente fout.
    func candidatesReadyForRetry(from allIDs: [String],
                                  now: Date = Date(),
                                  cooldown: TimeInterval = 3_600) -> [String] {
        let map = readMap()
        return allIDs.filter { id in
            guard let lastFailureTs = map[id] else { return true }
            let last = Date(timeIntervalSince1970: lastFailureTs)
            return now.timeIntervalSince(last) >= cooldown
        }
    }

    /// Aantal markers — handig voor tests + telemetrie.
    var markerCount: Int {
        readMap().count
    }

    // MARK: Private

    private func readMap() -> [String: Double] {
        defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    private func write(_ map: [String: Double]) {
        if map.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(map, forKey: Self.key)
        }
    }
}
