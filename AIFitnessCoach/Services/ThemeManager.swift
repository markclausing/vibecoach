import SwiftUI
import UIKit

// MARK: - ThemeManager

/// Manages the active theme, colour palettes and typography settings.
/// Use as an @EnvironmentObject from the root to guarantee app-wide reactivity.
@MainActor
final class ThemeManager: ObservableObject {

    @Published var currentTheme: Theme {
        didSet { UserDefaults.standard.set(currentTheme.rawValue, forKey: "vibecoach_selected_theme") }
    }

    /// Colour intensity of the whole app — 0.3 = very muted, 1.0 = full colour.
    @Published var themeSaturation: Double {
        didSet { UserDefaults.standard.set(themeSaturation, forKey: "vibecoach_theme_saturation") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "vibecoach_selected_theme") ?? ""
        currentTheme = Theme(rawValue: raw) ?? .moss

        let s = UserDefaults.standard.double(forKey: "vibecoach_theme_saturation")
        themeSaturation = s == 0 ? 1.0 : s
    }

    // MARK: - Adaptive colours (light/dark aware)

    /// Primary accent colour — adapts automatically to light/dark mode.
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

    /// Background colour — soft tint matching the theme.
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

    /// Soft gradient for backgrounds (two layers, top to bottom).
    var backgroundGradient: LinearGradient {
        let top    = backgroundColor
        let bottom = primaryAccentColor.opacity(0.08)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Icon helpers

    /// Returns the SF Symbol matching the active theme for a UI context.
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

}

/// UI contexts for which a theme-aware icon is available.
enum IconContext {
    case home
    case goal
    case theme
}

// MARK: - SereneIconStyle

/// Applies hierarchical SF Symbol rendering and the theme accent colour to an icon.
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

// MARK: - Haptics
// Light wrapper around UIKit feedback generators; used for confirmations (goal saved,
// message sent, onboarding completed) so key interactions feel tactile.
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
