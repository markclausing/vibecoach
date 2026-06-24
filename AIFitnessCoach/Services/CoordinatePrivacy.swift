import Foundation

// MARK: - Story 61.6 (security-review follow-up): single source of truth for coordinate privacy
//
// Every weather request rounds the GPS/geocoded coordinate to 0.1° (~11 km)
// before it leaves the device. The historical path already did this by
// construction; the live-forecast path (`WeatherManager`) and the per-stage path
// (`OpenMeteoForecastClient`) previously relied on `CLLocationManager`'s
// `desiredAccuracy` being coarse (review L-5). That made privacy fragile — a
// single future tightening of `desiredAccuracy` would silently start leaking
// fine GPS. Routing all three paths through this one helper makes the privacy
// margin explicit and independent of any accuracy setting.
//
// 0.1° is far more than enough for weather classification (temperature, rain,
// wind at a city scale) while removing street-level precision. Pure value-in/
// value-out (§6).
enum CoordinatePrivacy {

    /// Rounding granularity in degrees (~11 km at the equator).
    static let roundingDegrees: Double = 0.1

    /// Rounds a latitude or longitude to `roundingDegrees` before it is sent to a
    /// weather API, so the request never carries finer precision than ~11 km.
    static func round(_ degrees: Double) -> Double {
        (degrees / roundingDegrees).rounded() * roundingDegrees
    }
}
