import SwiftUI

// MARK: - Epic 18: Symptom Check-in Card

/// Daily pain score card. Only appears if the user has active injuries
/// (detected via UserPreference texts). Manages one score (0-10) per body area.
struct SymptomCheckinCard: View {
    let areas: [BodyArea]
    let todaySymptoms: [Symptom]
    let onSave: (BodyArea, Int) -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundStyle(themeManager.primaryAccentColor)
                Text("Hoe voelen je klachten vandaag?")
                    .font(.headline)
            }

            ForEach(areas, id: \.rawValue) { area in
                SymptomAreaRow(
                    area: area,
                    currentSeverity: todaySymptoms.first(where: { $0.bodyArea == area })?.severity ?? 0,
                    onSave: { severity in onSave(area, severity) }
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct SymptomAreaRow: View {
    let area: BodyArea
    let currentSeverity: Int
    let onSave: (Int) -> Void

    @State private var severity: Int
    @EnvironmentObject var themeManager: ThemeManager

    init(area: BodyArea, currentSeverity: Int, onSave: @escaping (Int) -> Void) {
        self.area = area
        self.currentSeverity = currentSeverity
        self.onSave = onSave
        self._severity = State(initialValue: currentSeverity)
    }

    private var severityColor: Color {
        switch severity {
        case 0:     return themeManager.primaryAccentColor
        case 1...3: return themeManager.primaryAccentColor
        case 4...6: return Color(red: 0.88, green: 0.58, blue: 0.32)
        default:    return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: area.icon)
                    .foregroundColor(severityColor)
                    .frame(width: 20)
                // Epic #37 story 37.4: BodyArea.rawValue / severityLabel stay Dutch (rawValue is
                // the SwiftData storage value; severityLabel feeds the coach prompt). The UI
                // resolves both via the catalog.
                Text(LocalizedStringKey(area.rawValue))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(severity)/10 — \(String(localized: String.LocalizationValue(BodyArea.severityLabel(severity))))")
                    .font(.caption)
                    .foregroundColor(severityColor)
                    .monospacedDigit()
            }
            // Compact +/- buttons (0-10, step 1)
            HStack(spacing: 8) {
                Button {
                    if severity > 0 {
                        severity -= 1
                        onSave(severity)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(severity > 0 ? .primary : .secondary)
                }
                .disabled(severity == 0)

                // Visual pain bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(severityColor)
                            .frame(width: severity == 0 ? 0 : geo.size.width * CGFloat(severity) / 10.0, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: severity)
                    }
                }
                .frame(height: 8)

                Button {
                    if severity < 10 {
                        severity += 1
                        onSave(severity)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(severity < 10 ? .primary : .secondary)
                }
                .disabled(severity == 10)
            }
        }
        .onChange(of: currentSeverity) { _, newValue in
            // Synchronize if the value changes externally (e.g. SwiftData refresh)
            if severity != newValue { severity = newValue }
        }
    }
}
