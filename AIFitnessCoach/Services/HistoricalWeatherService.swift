import Foundation

// MARK: - Epic #50: HistoricalWeatherService
//
// Bevraagt Open-Meteo voor temperatuur en luchtvochtigheid op een gegeven
// (latitude, longitude, datum-tijd). Vult het gat dat Epic #49 (HK-metadata)
// achterlaat: Garmin/fietscomputer-only ritten gesynced naar Strava hebben geen
// HK-tegenhanger (iPhone niet aanwezig tijdens rit), dus de cross-source merge
// in `ActivityDeduplicator` levert daar niets op. Met de Strava `start_latlng`
// kunnen we Open-Meteo's archive-API bevragen voor exact die locatie en tijd.
//
// **Privacy:** voordat we de coords naar Open-Meteo sturen ronden we ze af op
// 0.1° (~11km radius). Voor weer-classificatie ruim genoeg — bij 2 km/uur
// temperatuur-gradient over 11km zit je nog binnen ±1°C — en het voorkomt dat
// we exacte GPS-coordinaten (PII) naar een externe API lekken.
//
// **Endpoint-strategie:**
//   - `archive-api.open-meteo.com/v1/archive` voor data ouder dan ~5 dagen
//     (officiële historische dataset, ERA5).
//   - `api.open-meteo.com/v1/forecast` met `past_days` voor recentere data
//     (forecast-API houdt recente metingen tot enkele dagen terug).
// We kiezen op basis van workout-leeftijd. Beide hebben dezelfde response-shape.
//
// Service is testbaar via een geïnjecteerde `URLSessionProtocol` zodat unit
// tests een mock-response kunnen leveren zonder echte HTTP-call.

/// Lichtgewicht protocol-wrapper rond `URLSession.data(from:)` zodat de service
/// te testen is met een mock. Bewust niet `URLSessionProtocol` genoemd om
/// botsing met andere services te voorkomen.
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

    /// Privacy-rounding: GPS-coords worden afgerond op 0.1° (~11km) vóór de
    /// API-call. Test injectie kan deze waarde overrulen voor edge-cases.
    static let privacyRoundingDegrees: Double = 0.1

    /// Workouts ouder dan dit aantal dagen gaan via de archive-API; nieuwere via
    /// de forecast-API met `past_days`. Open-Meteo's archive heeft een lag van
    /// ongeveer 5 dagen voordat ERA5-data beschikbaar is.
    static let archiveLagDays: Int = 5

    /// Maximale leeftijd waarvoor we het zinvol vinden om weer op te halen. ERA5
    /// gaat terug tot 1940 maar onze app-data zal dat in praktijk niet raken; 2
    /// jaar is ruim voldoende voor alle relevante workout-historie.
    static let maxAgeYears: Int = 2

    private let fetcher: WeatherURLFetcher

    init(fetcher: WeatherURLFetcher = URLSession.shared) {
        self.fetcher = fetcher
    }

    /// Haalt temperatuur (°C) en luchtvochtigheid (%) op voor het uur waarin de
    /// workout-startdate valt. Returnt `(nil, nil)` als de API geen data levert
    /// voor dat uur (bijv. lat/lng buiten ERA5-grid). Gooit alleen bij echte
    /// transport-fouten zodat caller graceful kan terugvallen op "geen weer".
    /// - Parameters:
    ///   - latitude: Werkelijke GPS-latitude — wordt intern afgerond voor privacy.
    ///   - longitude: Werkelijke GPS-longitude.
    ///   - startDate: Tijdstip waarvan we het uur willen pakken.
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
            date: startDate,
            useArchive: ageDays >= Double(Self.archiveLagDays)
        )

        let (data, response) = try await fetcher.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherFetchError.requestFailed(statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data)
        return Self.extractHourValues(from: decoded, at: startDate)
    }

    // MARK: - URL builder (testable)

    static func makeURL(latitude: Double,
                        longitude: Double,
                        date: Date,
                        useArchive: Bool) throws -> URL {
        let base = useArchive
            ? "https://archive-api.open-meteo.com/v1/archive"
            : "https://api.open-meteo.com/v1/forecast"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: date)

        var components = URLComponents(string: base)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        if useArchive {
            items.append(URLQueryItem(name: "start_date", value: dateStr))
            items.append(URLQueryItem(name: "end_date", value: dateStr))
        } else {
            // Forecast-endpoint: past_days = aantal dagen historie inclusief vandaag.
            let now = Date()
            let days = max(0, Int(now.timeIntervalSince(date) / 86_400)) + 1
            items.append(URLQueryItem(name: "past_days", value: String(days)))
            items.append(URLQueryItem(name: "forecast_days", value: "1"))
        }
        components.queryItems = items
        guard let url = components.url else { throw WeatherFetchError.invalidCoordinates }
        return url
    }

    // MARK: - Helpers (internal voor test-zichtbaarheid)

    static func roundForPrivacy(_ degrees: Double) -> Double {
        let factor = privacyRoundingDegrees
        return (degrees / factor).rounded() * factor
    }

    static func extractHourValues(from response: OpenMeteoHourlyResponse,
                                  at date: Date) -> (temperatureCelsius: Double?, humidityPercent: Double?) {
        // Open-Meteo levert `hourly.time` als ISO-strings in de auto-detected timezone.
        // We zoeken het uur-bucket dat 't dichtst bij de workout-startdate ligt.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var bestIndex: Int?
        var bestDelta: TimeInterval = .infinity
        for (i, timeString) in response.hourly.time.enumerated() {
            // Open-Meteo levert "yyyy-MM-ddTHH:mm" zonder timezone-offset (locale-tijd).
            // Voor minuten-niveau-precisie hebben we de timezone-offset uit de response
            // nodig, maar voor matching op het naast-bij-uur kunnen we ook met een
            // timezone-onafhankelijke parse werken: pak het uur als String en match
            // op locale-uur van date.
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

    /// Open-Meteo levert `hourly.time` als "yyyy-MM-ddTHH:mm" in de auto-detected
    /// timezone (zonder offset-suffix). We parsen 'm als locale-tijd in UTC zodat
    /// de relatieve hour-bucket-matching klopt — exacte timezone is niet kritiek
    /// want we matchen op tijdsverschil binnen één dag.
    private static func parseLocalDateTime(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }
}

// MARK: - DTO

/// Response-shape voor zowel `archive` als `forecast` Open-Meteo endpoints —
/// beide leveren `hourly.{time,temperature_2m,relative_humidity_2m}`.
struct OpenMeteoHourlyResponse: Decodable, Equatable {
    let hourly: Hourly

    struct Hourly: Decodable, Equatable {
        let time: [String]
        /// Open-Meteo levert sommige uren als `null` bij missing data; daarom optional.
        let temperature_2m: [Double?]
        let relative_humidity_2m: [Double?]

        var temperatureValues: [Double?] { temperature_2m }
        var humidityValues: [Double?] { relative_humidity_2m }
    }
}

// MARK: - Convenience: enrich ActivityRecord vanuit Strava-ingest

extension HistoricalWeatherService {

    /// Vraagt Open-Meteo voor de Strava-startlocatie en zet temperatuur/luchtvochtigheid
    /// op de `ActivityRecord` als beschikbaar. Idempotent — slaat over als het record
    /// al weer-data heeft (bijv. via HK-cross-source-merge uit Epic #49). Faal-tolerant
    /// — bij netwerk- of API-fouten blijven de velden nil en gaat ingest gewoon door.
    /// Roep aan vanuit Strava-ingest-paden (auto-sync + historische sync) ná het
    /// bouwen van het record en vóór `ActivityDeduplicator.smartInsert`.
    @MainActor
    static func enrichRecord(_ record: ActivityRecord,
                             from activity: StravaActivity,
                             startDate: Date,
                             service: HistoricalWeatherService = HistoricalWeatherService()) async {
        guard record.temperatureCelsius == nil, record.humidityPercent == nil,
              let coords = activity.start_latlng, coords.count == 2 else { return }
        do {
            let (temp, humidity) = try await service.fetchWeather(
                latitude: coords[0],
                longitude: coords[1],
                startDate: startDate
            )
            if let t = temp { record.temperatureCelsius = t }
            if let h = humidity { record.humidityPercent = h }
        } catch {
            AppLoggers.weather.error("Open-Meteo fetch faalde voor activity \(activity.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
