import SwiftUI

/// V2.0 Sprint 1: Custom header for the dashboard.
/// Replaces the standard navigationTitle with a contextual greeting + day/phase indicator.
struct DashboardHeaderView: View {
    let periodizationResults: [PeriodizationResult]
    let goals: [FitnessGoal]

    @AppStorage("vibecoach_userName") private var userName: String = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = userName.isEmpty ? nil : userName.components(separatedBy: " ").first
        let suffix = firstName.map { ", \($0)" } ?? ""
        if hour < 12 { return "Goedemorgen\(suffix)" }
        if hour < 18 { return "Goedemiddag\(suffix)" }
        return "Goedenavond\(suffix)"
    }

    /// Builds the context line: "DONDERDAG 17 APR · BUILD PHASE · WK 2/5"
    private var contextLine: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.dateFormat = "EEEE d MMM"
        var parts: [String] = [formatter.string(from: Date()).uppercased()]

        if let result = periodizationResults.first {
            parts.append(result.phase.displayName.uppercased())

            if let goal = goals.first(where: { !$0.isCompleted && Date() < $0.targetDate }) {
                let cal = Calendar.current
                let totalWeeks = max(1, cal.dateComponents([.weekOfYear], from: goal.createdAt, to: goal.targetDate).weekOfYear ?? 1)
                let elapsedWeeks = max(1, cal.dateComponents([.weekOfYear], from: goal.createdAt, to: Date()).weekOfYear ?? 1)
                parts.append("WK \(min(elapsedWeeks, totalWeeks))/\(totalWeeks)")
            }
        }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contextLine)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .kerning(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(greeting)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        // Epic 43 Story 43.2: top-padding consistent with SettingsView, GoalsListView,
        // ChatView and PreferencesListView — otherwise the "Goedenavond" title slides
        // under the iPhone status bar (the clock overlaps with the text).
        .padding(.top, 56)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DashboardHeaderView")
    }
}

// MARK: - Epic 34.1: Scroll-aware material overlay for the status bar

/// ViewModifier that places a `regularMaterial` strip in the top safe area,
/// visible as soon as the underlying ScrollView has scrolled past the top.
/// Prevents content from visually sliding under the status bar.
private struct ScrollEdgeMaterialModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background {
                        Rectangle()
                            .fill(.regularMaterial)
                            .ignoresSafeArea(edges: .top)
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(false)
                    }
            }
    }
}

extension View {
    /// Shows a `regularMaterial` background in the top safe area as soon as `isActive` is true.
    func scrollEdgeMaterial(isActive: Bool) -> some View {
        modifier(ScrollEdgeMaterialModifier(isActive: isActive))
    }
}
