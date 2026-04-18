import SwiftUI

/// Beschikbare visuele thema's voor de VibeCoach app.
/// Elk thema heeft een eigen sfeer, kleurenpalet en iconografie.
enum Theme: String, Codable, CaseIterable {
    case moss
    case stone
    case mist
    case clay
    case sakura
    case ink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moss:   return "Mos"
        case .stone:  return "Steen"
        case .mist:   return "Nevel"
        case .clay:   return "Klei"
        case .sakura: return "Sakura"
        case .ink:    return "Inkt"
        }
    }

    var defaultIcon: String {
        switch self {
        case .moss:   return "leaf.fill"
        case .stone:  return "mountain.2.fill"
        case .mist:   return "cloud.fog.fill"
        case .clay:   return "circle.hexagongrid.fill"
        case .sakura: return "camera.macro"
        case .ink:    return "pencil.and.outline"
        }
    }
}
