import Foundation
import CoreLocation

// MARK: - Epic #56: location-aware per-stage weather for multi-day events
//
// Orchestrates the pieces: resolve a goal's route from its free text (RouteParser +
// CLGeocoder), interpolate the approximate location per stage day
// (StageLocationInterpolator), fetch that location's forecast (OpenMeteoForecastClient),
// and expose a per-date lookup the week schedule renders.
//
// The integration layer (network + CLGeocoder) is intentionally thin; all the logic that
// matters lives in the unit-tested pure helpers. Resolved routes and reverse-geocoded
// place names are cached in UserDefaults (derived data — no schema migration needed).
// Forecasts are refreshed live but throttled per session.

/// Weather at the approximate location of one event stage day.
struct StageWeather {
    let placeName: String?
    let forecast: DayForecast
}

@MainActor
final class StageWeatherService: ObservableObject {

    /// Keyed by start-of-day of the event date → the stage's location weather.
    @Published private(set) var stageWeather: [Date: StageWeather] = [:]

    private let geocoder = CLGeocoder()
    private let defaults: UserDefaults
    private let routeCacheKey = "vibecoach_eventRouteCache"
    private let placeCacheKey = "vibecoach_stagePlaceCache"

    /// Open-Meteo free tier provides ~16 forecast days; beyond that we show nothing.
    private let horizonDays = 16

    /// Guards against redundant refreshes within a session.
    private var lastSignature: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public

    /// Resolves routes + per-stage forecasts for the multi-day events that overlap the
    /// forecast horizon. Safe to call on every dashboard appear: it no-ops when nothing
    /// relevant changed.
    func refresh(goals: [FitnessGoal], now: Date = Date()) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let horizon = cal.date(byAdding: .day, value: horizonDays, to: today) else { return }

        // Earliest event wins on overlapping dates, mirroring WeekScheduleBuilder.
        let events = goals
            .filter { !$0.isCompleted && $0.resolvedEventDurationDays > 1 }
            .filter { cal.startOfDay(for: $0.targetDate) <= horizon }
            .filter { $0.eventEndDate >= today }
            .sorted { $0.targetDate < $1.targetDate }

        // Skip if nothing changed since the last refresh this session (ids + titles + today).
        let parts: [String] = events.map { "\($0.id.uuidString)|\($0.routeSourceText)" }
        let dayStamp = ISO8601DateFormatter().string(from: today)
        let signature = parts.joined(separator: ";") + "@" + dayStamp
        guard signature != lastSignature else { return }

        var result: [Date: StageWeather] = [:]
        var claimedDates = Set<Date>()

        for goal in events {
            guard let route = await resolveRoute(for: goal) else { continue }
            let total = goal.resolvedEventDurationDays

            for offset in 0..<total {
                guard let date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: goal.targetDate)) else { continue }
                let day = cal.startOfDay(for: date)
                guard day >= today, day <= horizon, !claimedDates.contains(day) else { continue }
                claimedDates.insert(day)

                let stageIndex = offset + 1
                let coord = StageLocationInterpolator.coordinate(
                    forStage: stageIndex, totalStages: total, start: route.start, end: route.end)

                guard let forecast = await forecast(at: coord, on: day, calendar: cal) else { continue }
                let place = await placeName(at: coord, stageIndex: stageIndex, route: route, total: total)
                result[day] = StageWeather(placeName: place, forecast: forecast)
            }
        }

        lastSignature = signature
        stageWeather = result
    }

    // MARK: - Route resolution (cached)

    private func resolveRoute(for goal: FitnessGoal) async -> EventRoute? {
        let source = goal.routeSourceText
        var cache = loadRouteCache()

        if let cached = cache[goal.id.uuidString], cached.sourceText == source {
            return cached.route   // may be nil = previously unresolvable; don't retry until text changes
        }

        var resolved: EventRoute?
        if let names = RouteParser.parse(source),
           let start = await geocode(names.start),
           let end = await geocode(names.end) {
            resolved = EventRoute(start: start, end: end, startName: names.start, endName: names.end)
        }

        cache[goal.id.uuidString] = CachedRoute(route: resolved, sourceText: source)
        saveRouteCache(cache)
        return resolved
    }

    private func geocode(_ place: String) async -> GeoCoordinate? {
        do {
            let placemarks = try await geocoder.geocodeAddressString(place)
            guard let loc = placemarks.first?.location else { return nil }
            return GeoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        } catch {
            AppLoggers.weather.error("Geocode faalde voor plaats: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Forecast + place name

    private func forecast(at coord: GeoCoordinate, on day: Date, calendar: Calendar) async -> DayForecast? {
        do {
            let forecasts = try await OpenMeteoForecastClient.fetchDailyForecast(
                latitude: coord.latitude, longitude: coord.longitude, days: horizonDays)
            return forecasts.first { calendar.isDate($0.date, inSameDayAs: day) }
        } catch {
            AppLoggers.weather.error("Etappe-forecast faalde: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reverse-geocoded locality near the interpolated point (cached). The endpoints reuse
    /// the parsed names so the first/last stage always read cleanly.
    private func placeName(at coord: GeoCoordinate, stageIndex: Int, route: EventRoute, total: Int) async -> String? {
        if stageIndex <= 1 { return route.startName }
        if stageIndex >= total { return route.endName }

        let key = String(format: "%.2f,%.2f", coord.latitude, coord.longitude)
        var cache = loadPlaceCache()
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        var name: String?
        do {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            name = placemarks.first?.locality ?? placemarks.first?.subAdministrativeArea
        } catch {
            AppLoggers.weather.error("Reverse-geocode faalde: \(error.localizedDescription, privacy: .public)")
        }
        cache[key] = name ?? ""   // cache the miss too, to avoid repeat lookups
        savePlaceCache(cache)
        return name
    }

    // MARK: - UserDefaults caches

    private struct CachedRoute: Codable {
        let route: EventRoute?
        let sourceText: String
    }

    private func loadRouteCache() -> [String: CachedRoute] {
        guard let data = defaults.data(forKey: routeCacheKey),
              let decoded = try? JSONDecoder().decode([String: CachedRoute].self, from: data) else { return [:] }
        return decoded
    }
    private func saveRouteCache(_ cache: [String: CachedRoute]) {
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: routeCacheKey) }
    }

    private func loadPlaceCache() -> [String: String] {
        (defaults.dictionary(forKey: placeCacheKey) as? [String: String]) ?? [:]
    }
    private func savePlaceCache(_ cache: [String: String]) {
        defaults.set(cache, forKey: placeCacheKey)
    }
}
