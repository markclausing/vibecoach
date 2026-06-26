import Foundation
import CoreLocation

// MARK: - Open-Meteo API response models

/// Decoding model for the Open-Meteo /v1/forecast daily response.
/// Documentation: https://open-meteo.com/en/docs
private struct OpenMeteoResponse: Decodable {
    let daily: OpenMeteoDailyData
}

private struct OpenMeteoDailyData: Decodable {
    let time: [String]                          // "yyyy-MM-dd"
    let temperature2mMax: [Double?]             // °C
    let temperature2mMin: [Double?]             // °C
    let precipitationProbabilityMax: [Double?]  // %  (0–100)
    let windSpeed10mMax: [Double?]              // km/h
    let weatherCode: [Int?]                     // WMO weather code

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax             = "temperature_2m_max"
        case temperature2mMin             = "temperature_2m_min"
        case precipitationProbabilityMax  = "precipitation_probability_max"
        case windSpeed10mMax              = "wind_speed_10m_max"
        case weatherCode                  = "weather_code"
    }
}

// MARK: - WeatherSafetyEvaluator

/// Pure decision logic for evaluating weather conditions for outdoor training.
/// Contains no network, location or UI dependencies — fully unit-testable.
struct WeatherSafetyEvaluator {

    /// Precipitation probability above this threshold (fraction 0–1) counts as a risk.
    static let precipitationRiskThreshold: Double = 0.60
    /// Wind speed (km/h) above this value counts as a risk.
    static let windRiskThresholdKmh: Double = 50.0
    /// Maximum temperature (°C) below this value: too-cold risk.
    static let coldRiskCelsius: Double = -5.0
    /// Maximum temperature (°C) above this value: heat-stress risk.
    static let heatRiskCelsius: Double = 38.0

    /// Returns true if the conditions pose a risk for outdoor training.
    /// - Parameters:
    ///   - precipitationProbability: Precipitation probability as a fraction 0.0–1.0.
    ///   - windSpeedKmh: Wind speed in km/h.
    ///   - highCelsius: The day's maximum temperature in °C.
    static func isRisky(
        precipitationProbability: Double,
        windSpeedKmh: Double,
        highCelsius: Double
    ) -> Bool {
        precipitationProbability > precipitationRiskThreshold ||
        windSpeedKmh             > windRiskThresholdKmh       ||
        highCelsius              < coldRiskCelsius             ||
        highCelsius              > heatRiskCelsius
    }
}

// MARK: - DayForecast

/// A compact daily weather forecast for training advice.
struct DayForecast: Identifiable {
    let id = UUID()
    let date: Date
    let highCelsius: Double
    let lowCelsius: Double
    /// Precipitation probability as a fraction 0.0–1.0.
    let precipitationProbability: Double
    let windSpeedKmh: Double
    let conditionDescription: String

    /// True if the conditions are bad for outdoor training.
    /// Delegates to WeatherSafetyEvaluator for isolated testability.
    var isRiskyForOutdoorTraining: Bool {
        WeatherSafetyEvaluator.isRisky(
            precipitationProbability: precipitationProbability,
            windSpeedKmh: windSpeedKmh,
            highCelsius: highCelsius
        )
    }
}

// MARK: - WeatherManager

/// Fetches the 7-day weather forecast via the free Open-Meteo API.
/// Requires only location permission — no API key or paid developer account needed.
@MainActor
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = WeatherManager()

    /// Daily weather forecast for the coming 7 days (index 0 = today).
    @Published var weeklyForecast: [DayForecast] = []

    /// True while the location or weather is being fetched.
    @Published var isLoading: Bool = false

    /// Error message if something went wrong, otherwise nil.
    @Published var errorMessage: String?

    private let locationManager = CLLocationManager()

    /// Callback invoked once the weather data is available.
    /// The argument is the formatted AI-context string.
    var onWeatherUpdated: ((String) -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    // MARK: - Public API

    /// Requests location permission and starts fetching the weather.
    /// If permission is already granted, a location update is requested directly.
    func requestWeatherIfNeeded() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            // No permission — fail silently, the coach works without weather data
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            await self.fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location error — ignore silently, the coach just works without weather data.
        // `Logger` is internally thread-safe, so no MainActor hop needed for the log.
        AppLoggers.weather.error("Locatiefout: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Open-Meteo fetch

    private func fetchWeather(for location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        // L-5: round to 0.1° before the request so privacy never depends on
        // CLLocationManager.desiredAccuracy (single source of truth: CoordinatePrivacy).
        let lat = CoordinatePrivacy.round(location.coordinate.latitude)
        let lon = CoordinatePrivacy.round(location.coordinate.longitude)

        // Open-Meteo free endpoint — no API key required.
        // daily parameters: temperature (min/max), precipitation probability, wind speed, weather code.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]

        guard let url = components.url else {
            AppLoggers.weather.error("Ongeldige URL")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30  // L-4: avoid a hung weather spinner (default is 60s)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response  = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            weeklyForecast = parseForecast(from: response.daily)

            let context = buildAIContext()
            onWeatherUpdated?(context)
            AppLoggers.weather.info("\(self.weeklyForecast.count, privacy: .public) dag(en) weerdata geladen via Open-Meteo")

        } catch {
            errorMessage = error.localizedDescription
            AppLoggers.weather.error("Fetch faalde: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Parser

    private func parseForecast(from daily: OpenMeteoDailyData) -> [DayForecast] {
        let dateParser = DateFormatter()
        dateParser.dateFormat = "yyyy-MM-dd"
        dateParser.locale = Locale(identifier: "en_US_POSIX")

        return daily.time.enumerated().compactMap { index, dateString in
            guard
                let date  = dateParser.date(from: dateString),
                let high  = daily.temperature2mMax[index],
                let low   = daily.temperature2mMin[index],
                let rain  = daily.precipitationProbabilityMax[index],
                let wind  = daily.windSpeed10mMax[index],
                let code  = daily.weatherCode[index]
            else { return nil }

            return DayForecast(
                date: date,
                highCelsius: high,
                lowCelsius: low,
                precipitationProbability: rain / 100.0,   // Open-Meteo returns %, we want 0–1
                windSpeedKmh: wind,
                conditionDescription: wmoDescription(code)
            )
        }
    }

    // MARK: - AI Context Builder

    /// Builds a structured text injected into the Gemini prompt.
    func buildAIContext() -> String {
        guard !weeklyForecast.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        formatter.locale = Locale(identifier: "nl_NL")

        var lines: [String] = []
        for day in weeklyForecast {
            let dayName = formatter.string(from: day.date)
            let tempStr = String(format: "%.0f–%.0f°C", day.lowCelsius, day.highCelsius)
            let rainStr = String(format: "%.0f%%", day.precipitationProbability * 100)
            let windStr = String(format: "%.0f km/u", day.windSpeedKmh)
            var line    = "• \(dayName): \(day.conditionDescription), \(tempStr), neerslag \(rainStr), wind \(windStr)"
            if day.isRiskyForOutdoorTraining {
                line += " ⚠️ BAD OUTDOOR WEATHER"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - WMO weather codes → Dutch description
    // WMO code definition: https://open-meteo.com/en/docs (section "Weather variable descriptions")

    // Epic #56: the WMO→Dutch mapping now lives in `OpenMeteoForecastClient` (single
    // source of truth, shared with the per-stage forecast fetch). Delegate to it.
    private func wmoDescription(_ code: Int) -> String {
        OpenMeteoForecastClient.conditionDescription(forWMOCode: code)
    }
}
