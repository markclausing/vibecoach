import Foundation
import CoreLocation

// MARK: - Open-Meteo API response modellen

/// Decoderingsmodel voor de Open-Meteo /v1/forecast daily-respons.
/// Documentatie: https://open-meteo.com/en/docs
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

// MARK: - DayForecast

/// Een compacte dagelijkse weersverwachting voor trainingsadvies.
struct DayForecast: Identifiable {
    let id = UUID()
    let date: Date
    let highCelsius: Double
    let lowCelsius: Double
    /// Neerslagkans als fractie 0.0–1.0.
    let precipitationProbability: Double
    let windSpeedKmh: Double
    let conditionDescription: String

    /// True als de omstandigheden slecht zijn voor een buitentraining.
    var isRiskyForOutdoorTraining: Bool {
        precipitationProbability > 0.60 ||
        windSpeedKmh > 50 ||
        highCelsius < -5 ||
        highCelsius > 38
    }
}

// MARK: - WeatherManager

/// Haalt via de gratis Open-Meteo API de weersverwachting op voor de komende 7 dagen.
/// Vereist alleen locatietoestemming — geen API-sleutel of betaald developer account nodig.
@MainActor
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = WeatherManager()

    /// Dagelijkse weersverwachting voor de komende 7 dagen (index 0 = vandaag).
    @Published var weeklyForecast: [DayForecast] = []

    /// True terwijl de locatie of het weer worden opgehaald.
    @Published var isLoading: Bool = false

    /// Foutmelding als er iets misging, anders nil.
    @Published var errorMessage: String? = nil

    private let locationManager = CLLocationManager()

    /// Callback die wordt aangeroepen zodra de weerdata beschikbaar is.
    /// Het argument is de geformatteerde AI-context string.
    var onWeatherUpdated: ((String) -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    // MARK: - Publieke API

    /// Vraagt locatiepermissie en start het ophalen van het weer.
    /// Bij al verleende toestemming wordt direct een locatie-update gevraagd.
    func requestWeatherIfNeeded() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            // Geen toestemming — stil falen, coach werkt zonder weerdata
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
        Task { @MainActor in
            // Locatiefout — stil negeren, coach werkt gewoon zonder weerdata
            print("⚠️ WeatherManager: Locatiefout — \(error.localizedDescription)")
        }
    }

    // MARK: - Open-Meteo fetch

    private func fetchWeather(for location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        // Open-Meteo gratis endpoint — geen API-sleutel vereist.
        // daily-parameters: temperatuur (min/max), neerslagkans, windsnelheid, weercode.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude",                        value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude",                       value: String(format: "%.4f", lon)),
            URLQueryItem(name: "daily",                           value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,weather_code"),
            URLQueryItem(name: "timezone",                        value: "auto"),
            URLQueryItem(name: "forecast_days",                   value: "7"),
        ]

        guard let url = components.url else {
            print("❌ WeatherManager: Ongeldige URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response  = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            weeklyForecast = parseForecast(from: response.daily)

            let context = buildAIContext()
            onWeatherUpdated?(context)
            print("☀️ WeatherManager: \(weeklyForecast.count) dag(en) weerdata geladen via Open-Meteo")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ WeatherManager: \(error.localizedDescription)")
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
                date:                    date,
                highCelsius:             high,
                lowCelsius:              low,
                precipitationProbability: rain / 100.0,   // Open-Meteo geeft % terug, wij willen 0–1
                windSpeedKmh:            wind,
                conditionDescription:    wmoDescription(code)
            )
        }
    }

    // MARK: - AI Context Builder

    /// Bouwt een gestructureerde tekst op die in de Gemini-prompt wordt geïnjecteerd.
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
                line += " ⚠️ SLECHT BUITENWEER"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - WMO weercodes → Nederlandse beschrijving
    // WMO code definitie: https://open-meteo.com/en/docs (paragraaf "Weather variable descriptions")

    private func wmoDescription(_ code: Int) -> String {
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
}
