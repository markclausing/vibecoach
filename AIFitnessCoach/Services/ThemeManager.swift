import SwiftUI
import UIKit

// MARK: - ThemeManager

/// Beheert het actieve thema, kleurenpaletten en typografie-instellingen.
/// Gebruik als @EnvironmentObject vanuit de root om app-brede reactiviteit te garanderen.
@MainActor
final class ThemeManager: ObservableObject {

    @Published var currentTheme: Theme {
        didSet { UserDefaults.standard.set(currentTheme.rawValue, forKey: "vibecoach_selected_theme") }
    }

    /// Schaalfactor voor koppen (0.8 = kleiner, 1.2 = groter).
    @Published var headingSizeMultiplier: Double {
        didSet { UserDefaults.standard.set(headingSizeMultiplier, forKey: "vibecoach_heading_size_multiplier") }
    }

    /// Schaalfactor voor bodytekst.
    @Published var bodySizeMultiplier: Double {
        didSet { UserDefaults.standard.set(bodySizeMultiplier, forKey: "vibecoach_body_size_multiplier") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "vibecoach_selected_theme") ?? ""
        currentTheme = Theme(rawValue: raw) ?? .moss

        let h = UserDefaults.standard.double(forKey: "vibecoach_heading_size_multiplier")
        headingSizeMultiplier = h == 0 ? 1.0 : h

        let b = UserDefaults.standard.double(forKey: "vibecoach_body_size_multiplier")
        bodySizeMultiplier = b == 0 ? 1.0 : b
    }

    // MARK: - Adaptieve kleuren (light/dark bewust)

    /// Primaire accentkleur — past automatisch aan op light/dark mode.
    var primaryAccentColor: Color {
        Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch self.currentTheme {
            case .moss:
                return dark ? UIColor(r: 0.52, g: 0.74, b: 0.52) : UIColor(r: 0.30, g: 0.50, b: 0.30)
            case .stone:
                return dark ? UIColor(r: 0.70, g: 0.67, b: 0.63) : UIColor(r: 0.47, g: 0.45, b: 0.43)
            case .mist:
                return dark ? UIColor(r: 0.58, g: 0.74, b: 0.86) : UIColor(r: 0.38, g: 0.54, b: 0.68)
            case .clay:
                return dark ? UIColor(r: 0.84, g: 0.60, b: 0.44) : UIColor(r: 0.68, g: 0.40, b: 0.26)
            case .sakura:
                return dark ? UIColor(r: 0.88, g: 0.66, b: 0.74) : UIColor(r: 0.70, g: 0.40, b: 0.52)
            case .ink:
                return dark ? UIColor(r: 0.52, g: 0.62, b: 0.82) : UIColor(r: 0.22, g: 0.28, b: 0.46)
            }
        })
    }

    /// Achtergrondkleur — zachte tint passend bij het thema.
    var backgroundColor: Color {
        Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch self.currentTheme {
            case .moss:   return dark ? UIColor(r: 0.10, g: 0.13, b: 0.10) : UIColor(r: 0.95, g: 0.97, b: 0.94)
            case .stone:  return dark ? UIColor(r: 0.12, g: 0.11, b: 0.10) : UIColor(r: 0.96, g: 0.95, b: 0.94)
            case .mist:   return dark ? UIColor(r: 0.08, g: 0.10, b: 0.14) : UIColor(r: 0.94, g: 0.96, b: 0.98)
            case .clay:   return dark ? UIColor(r: 0.14, g: 0.09, b: 0.07) : UIColor(r: 0.98, g: 0.95, b: 0.92)
            case .sakura: return dark ? UIColor(r: 0.13, g: 0.08, b: 0.10) : UIColor(r: 0.99, g: 0.95, b: 0.97)
            case .ink:    return dark ? UIColor(r: 0.07, g: 0.07, b: 0.10) : UIColor(r: 0.95, g: 0.95, b: 0.98)
            }
        })
    }

    /// Zacht gradient voor achtergronden (twee lagen, van boven naar onder).
    var backgroundGradient: LinearGradient {
        let top    = backgroundColor
        let bottom = primaryAccentColor.opacity(0.08)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Icoon helpers

    /// Geeft het SF Symbol terug dat bij het actieve thema past voor een UI-context.
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
            case .moss:   return "flag.2.crossed.fill"
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

    // MARK: - Typografie helpers

    /// Schaalt een font op basis van de heading-multiplier instelling.
    func scaledHeadingFont(_ style: Font.TextStyle = .headline) -> Font {
        Font.system(style).weight(.semibold).leading(.tight)
    }

    /// Schaalt een font op basis van de body-multiplier instelling.
    func scaledBodyFont(_ style: Font.TextStyle = .body) -> Font {
        Font.system(style).leading(.standard)
    }
}

/// UI-contexten waarvoor een themabewust icoon beschikbaar is.
enum IconContext {
    case home
    case goal
    case theme
}

// MARK: - SereneIconStyle

/// Past hiërarchische SF Symbol-rendering en de thema-accentkleur toe op een icoon.
struct SereneIconStyle: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
    }
}

extension View {
    func sereneIconStyle(color: Color) -> some View {
        modifier(SereneIconStyle(color: color))
    }
}

// MARK: - UIColor convenience init

private extension UIColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
