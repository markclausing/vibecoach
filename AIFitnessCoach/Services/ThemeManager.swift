import SwiftUI

/// Beheert het actieve visuele thema van de app.
/// Persisteert de keuze via @AppStorage zodat deze sessie-overstijgend bewaard blijft.
@MainActor
final class ThemeManager: ObservableObject {

    @AppStorage("vibecoach_selected_theme") private var storedTheme: String = Theme.moss.rawValue

    var currentTheme: Theme {
        get { Theme(rawValue: storedTheme) ?? .moss }
        set { storedTheme = newValue.rawValue }
    }

    // MARK: - Kleur helpers (placeholders — definitieve paletten volgen in Sprint 2)

    /// Primaire accentkleur van het actieve thema.
    var primaryAccentColor: Color {
        switch currentTheme {
        case .moss:   return Color(red: 0.35, green: 0.53, blue: 0.35)   // mosgroen
        case .stone:  return Color(red: 0.55, green: 0.55, blue: 0.52)   // grijssteen
        case .mist:   return Color(red: 0.65, green: 0.75, blue: 0.82)   // mistig blauw
        case .clay:   return Color(red: 0.72, green: 0.46, blue: 0.33)   // terracotta
        case .sakura: return Color(red: 0.90, green: 0.62, blue: 0.70)   // zachtroze
        case .ink:    return Color(red: 0.15, green: 0.15, blue: 0.20)   // diep inktblauw
        }
    }

    /// Achtergrondkleur van het actieve thema.
    var backgroundColor: Color {
        switch currentTheme {
        case .moss:   return Color(red: 0.94, green: 0.96, blue: 0.93)
        case .stone:  return Color(red: 0.95, green: 0.95, blue: 0.94)
        case .mist:   return Color(red: 0.93, green: 0.95, blue: 0.97)
        case .clay:   return Color(red: 0.97, green: 0.94, blue: 0.91)
        case .sakura: return Color(red: 0.99, green: 0.95, blue: 0.96)
        case .ink:    return Color(red: 0.10, green: 0.10, blue: 0.14)
        }
    }

    // MARK: - Icoon helpers

    /// Geeft het SF Symbol terug dat bij het actieve thema past voor een gegeven UI-context.
    func icon(for context: IconContext) -> String {
        switch context {
        case .home:
            switch currentTheme {
            case .moss:   return "house.and.flag.fill"
            case .stone:  return "house.lodge.fill"
            case .mist:   return "house.fill"
            case .clay:   return "fireplace.fill"
            case .sakura: return "house.circle.fill"
            case .ink:    return "building.2.fill"
            }
        case .goal:
            switch currentTheme {
            case .moss:   return "flag.and.flag.filled.crossed"
            case .stone:  return "mountain.2.fill"
            case .mist:   return "scope"
            case .clay:   return "trophy.fill"
            case .sakura: return "heart.circle.fill"
            case .ink:    return "target"
            }
        case .theme:
            return currentTheme.defaultIcon
        }
    }
}

/// UI-contexten waarvoor een themabewust icoon beschikbaar is.
enum IconContext {
    case home
    case goal
    case theme
}
