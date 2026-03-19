import Foundation

/// Data Transfer Object voor de Intervals.icu API response.
/// Bevat specifieke fysiologische en trainingsbelastingsmetrieken.
struct IntervalsActivity: Codable {
    let id: String
    let hrRecovery: Double?
    let tss: Double?
    let cardiacDrift: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case hrRecovery = "hr_recovery"
        case tss
        case cardiacDrift = "cardiac_drift"
    }
}
