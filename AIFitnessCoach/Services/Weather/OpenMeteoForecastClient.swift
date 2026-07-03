import Foundation

// MARK: - Epic #56: reusable Open-Meteo daily-forecast client for arbitrary coordinates
//
// `WeatherManager` fetches the forecast at the *device* location. For location-aware
// per-stage weather we need the same forecast at an arbitrary lat/lon, so this client
// owns the Open-Meteo `/v1/forecast` daily request, its decoding, and the WMO→Dutch
// condition mapping (the single source of truth — `WeatherManager` delegates to it).
//
// No API key required (Open-Meteo free tier). Returns `[DayForecast]`, the same value
// type used across the weather UI.

enum OpenMeteoForecastClient {

    /// One daily forecast entry per day, starting today, at the given coordinate.
    /// - Parameter days: number of forecast days (Open-Meteo free tier supports up to 16).
    static func fetchDailyForecast(latitude: Double, longitude: Double, days: Int = 16) async throws -> [DayForecast] {
        // L-5: round to 0.1° (~11 km) so the request never carries street-level
        // precision (single source of truth: CoordinatePrivacy).
        let roundedLat = CoordinatePrivacy.round(latitude)
        let roundedLon = CoordinatePrivacy.round(longitude)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", roundedLat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", roundedLon)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(min(max(days, 1), 16)))
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30  // L-4: avoid a hung weather spinner (default is 60s)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        return parse(response.daily)
    }

    // MARK: - WMO condition mapping (single source of truth)

    /// Maps a WMO weather code to a Dutch condition description. Used by both this client
    /// and `WeatherManager` so the two never drift apart.
    static func conditionDescription(forWMOCode code: Int) -> String {
        switch code {
        case 0:          return "Helder"
        case 1:          return "Overwegend helder"
        case 2:          return "Gedeeltelijk bewolkt"
        case 3:          return "Bewolkt"
        case 45, 48:     return "Mistig"
        case 51, 53:     return "Lichte motregen"
        case 55:         return "Dichte motregen"
        case 56, 57:     return "Bevriezende motregen"
        case 61, 63:     return "Lichte regen"
        case 65:         return "Zware regen"
        case 66, 67:     return "Bevriezende regen"
        case 71, 73:     return "Lichte sneeuw"
        case 75:         return "Zware sneeuw"
        case 77:         return "Sneeuwkorrels"
        case 80, 81:     return "Regenbuien"
        case 82:         return "Zware regenbuien"
        case 85, 86:     return "Sneeuwbuien"
        case 95:         return "Onweer"
        case 96, 99:     return "Onweer met hagel"
        default:         return "Wisselvallig"
        }
    }

    // MARK: - Decoding

    private static func parse(_ daily: OpenMeteoForecastDaily) -> [DayForecast] {
        let dateParser = AppDateFormatters.fixed("yyyy-MM-dd")

        return daily.time.enumerated().compactMap { index, dateString in
            guard
                let date = dateParser.date(from: dateString),
                let high = daily.temperature2mMax[index],
                let low  = daily.temperature2mMin[index],
                let rain = daily.precipitationProbabilityMax[index],
                let wind = daily.windSpeed10mMax[index],
                let code = daily.weatherCode[index]
            else { return nil }

            return DayForecast(
                date: date,
                highCelsius: high,
                lowCelsius: low,
                precipitationProbability: rain / 100.0,
                windSpeedKmh: wind,
                conditionDescription: conditionDescription(forWMOCode: code)
            )
        }
    }
}

// MARK: - Open-Meteo decoding models (file-level to keep nesting shallow)

private struct OpenMeteoForecastResponse: Decodable { let daily: OpenMeteoForecastDaily }

private struct OpenMeteoForecastDaily: Decodable {
    let time: [String]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]
    let precipitationProbabilityMax: [Double?]
    let windSpeed10mMax: [Double?]
    let weatherCode: [Int?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax            = "temperature_2m_max"
        case temperature2mMin            = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case windSpeed10mMax             = "wind_speed_10m_max"
        case weatherCode                 = "weather_code"
    }
}
