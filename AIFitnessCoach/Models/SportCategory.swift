import Foundation

/// Gestandaardiseerde sportcategorieën voor de applicatie (Epic 12 Refactor).
enum SportCategory: String, Codable, CaseIterable, Identifiable {
    case running = "running"
    case cycling = "cycling"
    case swimming = "swimming"
    case strength = "strength"
    case walking = "walking"
    case triathlon = "triathlon"
    case other = "other"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .running: return "Hardlopen"
        case .cycling: return "Wielrennen"
        case .swimming: return "Zwemmen"
        case .strength: return "Krachttraining"
        case .walking: return "Wandelen"
        case .triathlon: return "Triatlon"
        case .other: return "Anders"
        }
    }

    /// Menselijke naam voor gebruik in coach-context en banners (bijv. "hardloopsessie", "fietstocht").
    /// Zorgt dat de AI nooit technische termen zoals 'HealthKit 52' gebruikt.
    var workoutName: String {
        switch self {
        case .running:   return "hardloopsessie"
        case .cycling:   return "fietstocht"
        case .swimming:  return "zwemsessie"
        case .strength:  return "krachttraining"
        case .walking:   return "wandeling"
        case .triathlon: return "triatlonsessie"
        case .other:     return "training"
        }
    }

    /// Mapt direct vanaf een HealthKit type voor robuustheid in plaats van string beschrijvingen
    static func from(hkType: UInt) -> SportCategory {
        // We gebruiken UInt omdat we HealthKit hier wellicht niet expliciet willen importeren op elke plek
        // 13 = cycling, 37 = running, 52 = walking, 16 = elliptical, 50 = traditionalStrengthTraining, 82 = swimming
        switch hkType {
        case 13: return .cycling
        case 37: return .running
        case 46, 82: return .swimming
        case 50, 59: return .strength
        case 52: return .walking
        case 83: return .triathlon
        default: return .other
        }
    }

    /// Factory methode om ruwe externe API strings (zoals "Ride")
    /// robuust te mappen naar de gestandaardiseerde `SportCategory`.
    static func from(rawString: String?) -> SportCategory {
        guard let raw = rawString?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .other
        }

        if raw.contains("run") || raw.contains("hardlopen") || raw == "hkworkoutactivitytyperunning" {
            return .running
        }

        if raw.contains("ride") || raw.contains("cycl") || raw.contains("fiets") || raw.contains("wielrennen") || raw == "hkworkoutactivitytypecycling" {
            return .cycling
        }

        if raw.contains("swim") || raw.contains("zwem") || raw == "hkworkoutactivitytypeswimming" {
            return .swimming
        }

        if raw.contains("strength") || raw.contains("weight") || raw.contains("kracht") || raw == "hkworkoutactivitytypetraditionalstrengthtraining" {
            return .strength
        }

        if raw.contains("walk") || raw.contains("wandelen") || raw == "hkworkoutactivitytypewalking" {
            return .walking
        }

        if raw.contains("triathlon") || raw.contains("triatlon") {
            return .triathlon
        }

        return .other
    }
}
