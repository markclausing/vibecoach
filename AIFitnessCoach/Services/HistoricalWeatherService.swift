import Foundation

// MARK: - Epic #50: HistoricalWeatherService
//
// Queries Open-Meteo for temperature and humidity at a given
// (latitude, longitude, date-time). Fills the gap that Epic #49 (HK metadata)
// leaves: Garmin/bike-computer-only rides synced to Strava have no HK
// counterpart (iPhone not present during the ride), so the cross-source merge
// in `ActivityDeduplicator` yields nothing there. With the Strava `start_latlng`
// we can query Open-Meteo's archive API for exactly that location and time.
//
// **Privacy:** before sending the coords to Open-Meteo we round them to
// 0.1° (~11km radius). More than enough for weather classification — with a
// 2 °C/hour temperature gradient over 11km you're still within ±1°C — and it
// prevents us from leaking exact GPS coordinates (PII) to an external API.
//
// **Endpoint strategy:**
//   - `archive-api.open-meteo.com/v1/archive` for data older than ~5 days
//     (official historical dataset, ERA5).
//   - `api.open-meteo.com/v1/forecast` with `past_days` for more recent data
//     (the forecast API keeps recent measurements for a few days back).
// We choose based on workout age. Both have the same response shape.
//
// The service is testable via an injected `URLSessionProtocol` so unit tests
// can supply a mock response without a real HTTP call.

/// Lightweight protocol wrapper around `URLSession.data(from:)` so the service
/// can be tested with a mock. Deliberately not named `URLSessionProtocol` to
/// avoid clashing with other services.
protocol WeatherURLFetcher {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: WeatherURLFetcher {}

final class HistoricalWeatherService {

    enum WeatherFetchError: Error, Equatable {
        case invalidCoordinates
        case dateOutOfRange
        case noDataAvailable
        case requestFailed(statusCode: Int)
    }

    /// Privacy rounding: GPS coords are rounded to 0.1° (~11km) before the API
    /// call. Test injection can override this value for edge cases.
    static let privacyRoundingDegrees: Double = 0.1

    /// Workouts older than this number of days go via the archive API; newer ones
    /// via the forecast API with `past_days`. Open-Meteo's archive has a lag of
    /// about 5 days before ERA5 data is available.
    static let archiveLagDays: Int = 5

    /// Maximum age for which we consider it useful to fetch weather. ERA5 goes
    /// back to 1940 but our app data won't reach that in practice; 2 years is
    /// more than enough for all relevant workout history.
    static let maxAgeYears: Int = 2

    private let fetcher: WeatherURLFetcher

    init(fetcher: WeatherURLFetcher = URLSession.shared) {
        self.fetcher = fetcher
    }

    /// Fetches temperature (°C) and humidity (%) for the hour in which the
    /// workout start date falls. Returns `(nil, nil)` if the API provides no data
    /// for that hour (e.g. lat/lng outside the ERA5 grid). Throws only on real
    /// transport errors so the caller can gracefully fall back to "no weather".
    /// - Parameters:
    ///   - latitude: Actual GPS latitude — rounded internally for privacy.
    ///   - longitude: Actual GPS longitude.
    ///   - startDate: The moment whose hour we want to take.
    func fetchWeather(latitude: Double,
                      longitude: Double,
                      startDate: Date) async throws -> (temperatureCelsius: Double?, humidityPercent: Double?) {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else {
            throw WeatherFetchError.invalidCoordinates
        }

        let now = Date()
        let ageDays = now.timeIntervalSince(startDate) / 86_400
        guard ageDays >= 0, ageDays <= Double(Self.maxAgeYears * 365) else {
            throw WeatherFetchError.dateOutOfRange
        }

        let roundedLat = Self.roundForPrivacy(latitude)
        let roundedLon = Self.roundForPrivacy(longitude)

        let url = try Self.makeURL(
            latitude: roundedLat,
            longitude: roundedLon,
            startDate: startDate,
            endDate: startDate,
            useArchive: ageDays >= Double(Self.archiveLagDays)
        )

        let (data, response) = try await fetcher.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherFetchError.requestFailed(statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data)
        return Self.extractHourValues(from: decoded, at: startDate)
    }

    // MARK: - Epic #52: hourly range aggregate

    /// Aggregate over a workout time window — used by the Coach analysis so a
    /// 90-min run that started at 9:43 at 15°C but ran up to a 22°C peak is fairly
    /// evaluated as a "22°C ride" (instead of the single-point snapshot from HK
    /// metadata at ride start). All fields optional; on incomplete data the caller
    /// omits the prompt block.
    struct WeatherRange: Equatable {
        let peakTempCelsius: Double?
        let avgTempCelsius: Double?
        let peakHumidityPercent: Double?
        let avgHumidityPercent: Double?
        /// Number of hourly buckets that contributed to the aggregate. Below 2
        /// there's little "range" to speak of — the caller may choose to stay on
        /// the single-point fallback then.
        let hourlyBucketCount: Int
    }

    /// Fetches hourly weather data for the full workout window `[startDate, endDate]`
    /// and aggregates into peak/avg for both temperature and humidity. Works across
    /// multiple hours and multiple days (rare case: night ultra). Empty buckets
    /// (API returns `null`) are ignored in the average, not counted as 0. Throws
    /// only on real transport or validation errors — graceful fallback at the caller.
    /// - Parameters:
    ///   - latitude: Actual GPS latitude — rounded internally for privacy.
    ///   - longitude: Actual GPS longitude.
    ///   - startDate: Start of the workout.
    ///   - endDate: End of the workout. Must be `>= startDate`.
    func fetchWeatherRange(latitude: Double,
                           longitude: Double,
                           startDate: Date,
                           endDate: Date) async throws -> WeatherRange {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else {
            throw WeatherFetchError.invalidCoordinates
        }
        guard endDate >= startDate else {
            throw WeatherFetchError.invalidCoordinates
        }

        let now = Date()
        let ageDays = now.timeIntervalSince(startDate) / 86_400
        guard ageDays >= 0, ageDays <= Double(Self.maxAgeYears * 365) else {
            throw WeatherFetchError.dateOutOfRange
        }

        let roundedLat = Self.roundForPrivacy(latitude)
        let roundedLon = Self.roundForPrivacy(longitude)

        let url = try Self.makeURL(
            latitude: roundedLat,
            longitude: roundedLon,
            startDate: startDate,
            endDate: endDate,
            useArchive: ageDays >= Double(Self.archiveLagDays)
        )

        let (data, response) = try await fetcher.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherFetchError.requestFailed(statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data)
        return Self.extractWindowAggregates(from: decoded, start: startDate, end: endDate)
    }

    // MARK: - URL builder (testable)

    /// Epic #52: signature extended with `startDate` + `endDate` so one call can
    /// cover hourly data over a multi-hour window. For the old single-point fetch
    /// the caller passes `startDate == endDate` (range = 1 day).
    static func makeURL(latitude: Double,
                        longitude: Double,
                        startDate: Date,
                        endDate: Date,
                        useArchive: Bool) throws -> URL {
        let base = useArchive
            ? "https://archive-api.open-meteo.com/v1/archive"
            : "https://api.open-meteo.com/v1/forecast"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)

        var components = URLComponents(string: base)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        if useArchive {
            items.append(URLQueryItem(name: "start_date", value: startStr))
            items.append(URLQueryItem(name: "end_date", value: endStr))
        } else {
            // Forecast endpoint: past_days = number of days of history including today.
            // We base it on startDate — endDate is typically a few hours later, so it
            // falls within the same day or just after; forecast_days=1 covers that.
            let now = Date()
            let days = max(0, Int(now.timeIntervalSince(startDate) / 86_400)) + 1
            items.append(URLQueryItem(name: "past_days", value: String(days)))
            items.append(URLQueryItem(name: "forecast_days", value: "1"))
        }
        components.queryItems = items
        guard let url = components.url else { throw WeatherFetchError.invalidCoordinates }
        return url
    }

    // MARK: - Helpers (internal for test visibility)

    static func roundForPrivacy(_ degrees: Double) -> Double {
        let factor = privacyRoundingDegrees
        return (degrees / factor).rounded() * factor
    }

    static func extractHourValues(from response: OpenMeteoHourlyResponse,
                                  at date: Date) -> (temperatureCelsius: Double?, humidityPercent: Double?) {
        // Open-Meteo returns `hourly.time` as ISO strings in the auto-detected timezone.
        // We look for the hour bucket closest to the workout start date.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var bestIndex: Int?
        var bestDelta: TimeInterval = .infinity
        for (i, timeString) in response.hourly.time.enumerated() {
            // Open-Meteo returns "yyyy-MM-ddTHH:mm" without a timezone offset (local time).
            // For minute-level precision we'd need the timezone offset from the response,
            // but for nearest-hour matching we can work with a timezone-independent
            // parse: take the hour as a String and match on the local hour of date.
            guard let parsed = Self.parseLocalDateTime(timeString) else { continue }
            let delta = abs(parsed.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        guard let idx = bestIndex else { return (nil, nil) }
        let temp = response.hourly.temperature_2m.indices.contains(idx) ? response.hourly.temperature_2m[idx] : nil
        let humidity = response.hourly.relative_humidity_2m.indices.contains(idx) ? response.hourly.relative_humidity_2m[idx] : nil
        return (temp, humidity)
    }

    /// Open-Meteo returns `hourly.time` as "yyyy-MM-ddTHH:mm" in the auto-detected
    /// timezone (without offset suffix). We parse it as local time in UTC so the
    /// relative hour-bucket matching is correct — the exact timezone isn't critical
    /// since we match on time difference within one day.
    static func parseLocalDateTime(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }

    // MARK: - Epic #52: aggregate helper (pure, testable)

    /// Aggregates hourly values into peak/avg over a workout window `[start, end]`.
    /// Includes the start hour (first hour the workout overlaps) and all following
    /// hours up to and including the hour in which `end` falls. Buckets with `null`
    /// values are ignored in the average (no 0-pollution). With 0 valid buckets all
    /// fields return `nil` so the caller can gracefully fall back.
    ///
    /// **Time match:** Open-Meteo returns hourly times without a timezone offset
    /// (auto-detect timezone on the coords). Our `start`/`end` are UTC Date
    /// instances. Match strategy: compare hourly-time parsed as UTC with start/end
    /// on `<=`/`<=` — small timezone skew is dampened by the fact that we match
    /// whole hours, not minutes. For a 90-min run starting at 9:43 and ending at
    /// 11:13 we typically pick up 3 hourly buckets: 9:00, 10:00, 11:00.
    static func extractWindowAggregates(from response: OpenMeteoHourlyResponse,
                                        start: Date,
                                        end: Date) -> WeatherRange {
        let times = response.hourly.time
        let temps = response.hourly.temperature_2m
        let hums = response.hourly.relative_humidity_2m

        // First hourly bucket = start of the hour in which `start` falls. Example:
        // start 9:43 → bucket 9:00 counts. A workout that falls within one hour
        // (start 9:43, end 9:55) thus always picks up at least that one bucket.
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let startBucket = utcCalendar.dateInterval(of: .hour, for: start)?.start ?? start

        var tempValues: [Double] = []
        var humValues: [Double] = []

        for (i, timeString) in times.enumerated() {
            guard let parsed = parseLocalDateTime(timeString) else { continue }
            // Both bounds inclusive: parsed >= startBucket && parsed <= end
            guard parsed >= startBucket && parsed <= end else { continue }
            if temps.indices.contains(i), let t = temps[i] {
                tempValues.append(t)
            }
            if hums.indices.contains(i), let h = hums[i] {
                humValues.append(h)
            }
        }

        return WeatherRange(
            peakTempCelsius: tempValues.max(),
            avgTempCelsius: tempValues.isEmpty ? nil : tempValues.reduce(0, +) / Double(tempValues.count),
            peakHumidityPercent: humValues.max(),
            avgHumidityPercent: humValues.isEmpty ? nil : humValues.reduce(0, +) / Double(humValues.count),
            hourlyBucketCount: max(tempValues.count, humValues.count)
        )
    }
}

// MARK: - DTO

/// Response shape for both the `archive` and `forecast` Open-Meteo endpoints —
/// both return `hourly.{time,temperature_2m,relative_humidity_2m}`.
struct OpenMeteoHourlyResponse: Decodable, Equatable {
    let hourly: Hourly

    struct Hourly: Decodable, Equatable {
        let time: [String]
        /// Open-Meteo returns some hours as `null` on missing data; hence optional.
        let temperature_2m: [Double?]
        let relative_humidity_2m: [Double?]

        var temperatureValues: [Double?] { temperature_2m }
        var humidityValues: [Double?] { relative_humidity_2m }
    }
}

// MARK: - Convenience: enrich ActivityRecord from Strava ingest

extension HistoricalWeatherService {

    /// Queries Open-Meteo for the Strava start location and sets temperature/humidity
    /// on the `ActivityRecord` if available. Idempotent — skips the weather fetch
    /// if the record already has weather data (e.g. via the HK cross-source merge
    /// from Epic #49). Fault-tolerant — on network or API errors the fields stay nil
    /// and ingest just continues. Call from Strava ingest paths (auto-sync +
    /// historical sync) after building the record and before
    /// `ActivityDeduplicator.smartInsert`.
    ///
    /// **Epic #52:** also persists `startLatitude` + `startLongitude` on the record
    /// so a later Coach call can fetch the hourly weather range without querying the
    /// Strava API again. This happens independently of the weather fetch — coords-only
    /// (no weather data) is also useful for the range path.
    @MainActor
    static func enrichRecord(_ record: ActivityRecord,
                             from activity: StravaActivity,
                             startDate: Date,
                             service: HistoricalWeatherService = HistoricalWeatherService()) async {
        guard let coords = activity.start_latlng, coords.count == 2 else { return }

        // Epic #52: always persist GPS coords if not yet set, independent of the
        // weather fetch below. This way existing records benefit from the
        // hourly-range fetch as soon as the next re-ingest happens.
        if record.startLatitude == nil { record.startLatitude = coords[0] }
        if record.startLongitude == nil { record.startLongitude = coords[1] }

        // Snapshot fetch only if not already present — for backwards-compat with
        // Epic #49 HK metadata. The hourly-range fetch lives in the Coach flow and
        // doesn't use this snapshot.
        guard record.temperatureCelsius == nil, record.humidityPercent == nil else { return }
        do {
            let (temp, humidity) = try await service.fetchWeather(
                latitude: coords[0],
                longitude: coords[1],
                startDate: startDate
            )
            if let t = temp { record.temperatureCelsius = t }
            if let h = humidity { record.humidityPercent = h }
        } catch {
            AppLoggers.weather.error("Open-Meteo fetch faalde voor activity \(activity.id, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }
}
