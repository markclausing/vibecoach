import Foundation
import CoreLocation
import WeatherKit

/// Weerscondities die relevant zijn voor trainingsadvies.
struct TrainingWeatherCondition: Equatable {
    let temperatureCelsius: Double
    let precipitationProbability: Double  // 0.0–1.0
    let windSpeedKmh: Double
    let conditionDescription: String      // "Zwaar bewolkt", "Lichte regen", etc.
    let uvIndex: Int

    /// Geeft een leesbare samenvatting terug voor de AI-prompt.
    var aiSummary: String {
        let tempStr   = String(format: "%.0f°C", temperatureCelsius)
        let windStr   = String(format: "%.0f km/u", windSpeedKmh)
        let rainStr   = String(format: "%.0f%%", precipitationProbability * 100)
        return "\(conditionDescription), \(tempStr), wind \(windStr), neerslag \(rainStr), UV-index \(uvIndex)"
    }

    /// True als de omstandigheden slecht zijn voor een buitentraining.
    var isOutdoorTrainingRisky: Bool {
        precipitationProbability > 0.60 ||
        windSpeedKmh > 50 ||
        temperatureCelsius < -5 ||
        temperatureCelsius > 38
    }
}

/// Haalt via Apple WeatherKit de weersverwachting op voor de komende 7 dagen.
/// Vereist WeatherKit capability + een actieve Apple Developer sessie.
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
    private let weatherService = WeatherService.shared

    /// Callback die wordt aangeroepen zodra de weerdata beschikbaar is.
    var onWeatherUpdated: ((String) -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    // MARK: - Publieke API

    /// Vraagt locatiepermissie en start het ophalen van het weer.
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
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
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
            // Locatiefout — stil negeren, coach werkt zonder weerdata
            print("⚠️ WeatherManager: Locatiefout — \(error.localizedDescription)")
        }
    }

    // MARK: - WeatherKit fetch

    private func fetchWeather(for location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let weather = try await weatherService.weather(
                for: location,
                including: .daily
            )

            // Bouw een compacte DayForecast-array op voor de komende 7 dagen
            weeklyForecast = weather.forecast.prefix(7).map { day in
                DayForecast(
                    date:                     day.date,
                    highCelsius:              day.highTemperature.converted(to: .celsius).value,
                    lowCelsius:               day.lowTemperature.converted(to: .celsius).value,
                    precipitationProbability: day.precipitationChance,
                    windSpeedKmh:             day.wind.speed.converted(to: .kilometersPerHour).value,
                    conditionDescription:     day.condition.dutchDescription,
                    uvIndex:                  day.uvIndex.value
                )
            }

            // Stuur de gegenereerde AI-context terug via de callback
            let context = buildAIContext()
            onWeatherUpdated?(context)
            print("☀️ WeatherManager: \(weeklyForecast.count) dag(en) weerdata geladen")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ WeatherManager: \(error.localizedDescription)")
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
            var line = "• \(dayName): \(day.conditionDescription), \(tempStr), neerslag \(rainStr), wind \(windStr)"
            if day.isRiskyForOutdoorTraining {
                line += " ⚠️ SLECHT BUITENWEER"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - DayForecast

/// Een compacte dagelijkse weersverwachting voor trainingsadvies.
struct DayForecast: Identifiable {
    let id = UUID()
    let date: Date
    let highCelsius: Double
    let lowCelsius: Double
    let precipitationProbability: Double
    let windSpeedKmh: Double
    let conditionDescription: String
    let uvIndex: Int

    var isRiskyForOutdoorTraining: Bool {
        precipitationProbability > 0.60 ||
        windSpeedKmh > 50 ||
        highCelsius < -5 ||
        highCelsius > 38
    }
}

// MARK: - WeatherCondition Lokalisatie

extension WeatherCondition {
    /// Vertaalt de Apple WeatherKit conditie naar een Nederlandse beschrijving.
    var dutchDescription: String {
        switch self {
        case .clear:             return "Helder"
        case .mostlyClear:       return "Overwegend helder"
        case .partlyCloudy:      return "Gedeeltelijk bewolkt"
        case .mostlyCloudy:      return "Overwegend bewolkt"
        case .cloudy:            return "Bewolkt"
        case .foggy:             return "Mistig"
        case .haze:              return "Wazig"
        case .windy:             return "Winderig"
        case .breezy:            return "Fris briesje"
        case .drizzle:           return "Motregen"
        case .rain:              return "Regen"
        case .heavyRain:         return "Zware regen"
        case .flurries:          return "Sneeuwbuien"
        case .snow:              return "Sneeuw"
        case .blizzard:          return "Sneeuwstorm"
        case .sleet:             return "Ijzel"
        case .freezingDrizzle:   return "Bevriezing nevel"
        case .freezingRain:      return "Bevriezende regen"
        case .thunderstorms:     return "Onweer"
        case .hurricane:         return "Orkaan"
        case .tropicalStorm:     return "Tropische storm"
        case .hail:              return "Hagel"
        case .hot:               return "Erg heet"
        case .blowingDust:       return "Stof"
        case .smoky:             return "Rookoverlast"
        case .frigid:            return "Strenge vorst"
        @unknown default:        return "Onbekend"
        }
    }
}
