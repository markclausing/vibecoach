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

    /// Vaste previewkleur voor de thema-picker (niet light/dark adaptief).
    var previewColor: Color {
        switch self {
        case .moss:   return Color(red: 0.30, green: 0.50, blue: 0.30)
        case .stone:  return Color(red: 0.47, green: 0.45, blue: 0.43)
        case .mist:   return Color(red: 0.38, green: 0.54, blue: 0.68)
        case .clay:   return Color(red: 0.68, green: 0.40, blue: 0.26)
        case .sakura: return Color(red: 0.80, green: 0.52, blue: 0.62)
        case .ink:    return Color(red: 0.22, green: 0.28, blue: 0.46)
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
