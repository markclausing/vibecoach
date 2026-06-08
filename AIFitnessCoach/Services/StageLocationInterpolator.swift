import Foundation

// MARK: - Epic #56 story 56.2: per-stage location interpolation
//
// Pure-Swift, AppStorage-free (CLAUDE.md §6). Given a route start and end and a total
// number of stages, returns the approximate coordinate for a given 1-based stage: day 1
// sits at the start, day N at the end, and the days in between are spread evenly along
// the great-circle (slerp) between them. Great-circle (not naive lat/lon-linear) keeps
// the midpoint correct over longer routes; for short routes the two are nearly identical.

enum StageLocationInterpolator {

    /// Approximate coordinate for `stage` (1-based) of `totalStages`.
    /// - `stage <= 1` → start; `stage >= totalStages` → end; otherwise an evenly spaced
    ///   point along the great-circle. `totalStages <= 1` always returns the start.
    static func coordinate(forStage stage: Int,
                           totalStages: Int,
                           start: GeoCoordinate,
                           end: GeoCoordinate) -> GeoCoordinate {
        guard totalStages > 1 else { return start }
        let clamped = min(max(stage, 1), totalStages)
        let fraction = Double(clamped - 1) / Double(totalStages - 1)
        return interpolate(from: start, to: end, fraction: fraction)
    }

    /// Great-circle interpolation (slerp) at `fraction` in [0, 1].
    static func interpolate(from start: GeoCoordinate, to end: GeoCoordinate, fraction t: Double) -> GeoCoordinate {
        if t <= 0 { return start }
        if t >= 1 { return end }

        let φ1 = start.latitude  * .pi / 180
        let λ1 = start.longitude * .pi / 180
        let φ2 = end.latitude    * .pi / 180
        let λ2 = end.longitude   * .pi / 180

        // Angular distance between the two points (haversine, numerically stable).
        let dφ = φ2 - φ1
        let dλ = λ2 - λ1
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        let δ = 2 * atan2(sqrt(a), sqrt(1 - a))

        // Coincident (or numerically tiny) → fall back to linear to avoid /sin(δ).
        guard δ > 1e-9 else {
            return GeoCoordinate(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            )
        }

        let A = sin((1 - t) * δ) / sin(δ)
        let B = sin(t * δ) / sin(δ)

        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)

        let φi = atan2(z, sqrt(x * x + y * y))
        let λi = atan2(y, x)

        return GeoCoordinate(latitude: φi * 180 / .pi, longitude: λi * 180 / .pi)
    }
}
