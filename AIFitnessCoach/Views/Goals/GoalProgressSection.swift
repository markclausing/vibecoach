import SwiftUI

/// Epic #72 story 72.2: extracted from GoalsListView (pure move; restyled in story 72.3).
/// Story 72.3: per-metric status pills reuse `GoalVerdictBuilder.paceStatus` so a row can never
/// disagree with the verdict banner above it; the max-metric (longest session) gets an "achieved"
/// row without a progress bar once met, per docs/design/goals-redesign.html.
struct GoalProgressSection: View {
    let gap: BlueprintGap
    let periResult: PeriodizationResult?
    @EnvironmentObject var themeManager: ThemeManager

    /// True when at least one rendered row shows an expected-today reference marker,
    /// which is when the legend line below the card is relevant.
    private var showsLegend: Bool {
        gap.trimpReferencePct > 0 || (gap.totalPhaseKmTarget > 0 && gap.kmReferencePct > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOORTGANG DEZE FASE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            VStack(alignment: .leading, spacing: 8) {
                // Training load (TRIMP)
                ProgressRow(
                    icon: "bolt.fill",
                    label: "Trainingsbelasting",
                    valueCurrent: String(format: "%.0f", gap.actualTRIMPToDate),
                    valueTarget: String(format: "%.0f", gap.totalPhaseTRIMPTarget),
                    unit: "TRIMP",
                    progress: gap.trimpProgressPct,
                    reference: gap.trimpReferencePct,
                    actualValue: gap.actualTRIMPToDate,
                    expectedValue: gap.requiredTRIMPToDate,
                    gapFloor: GoalVerdictBuilder.trimpGapFloor,
                    showsPill: true,
                    accentColor: themeManager.primaryAccentColor
                )
                // Distance
                if gap.totalPhaseKmTarget > 0 {
                    let sportLabel = gap.blueprintType == .cyclingTour ? "Afstand (wielrennen)" : "Afstand (hardlopen)"
                    ProgressRow(
                        icon: "chart.line.uptrend.xyaxis",
                        label: sportLabel,
                        valueCurrent: String(format: "%.0f", gap.actualKmToDate),
                        valueTarget: String(format: "%.0f", gap.totalPhaseKmTarget),
                        unit: "km",
                        progress: gap.kmProgressPct,
                        reference: gap.kmReferencePct,
                        actualValue: gap.actualKmToDate,
                        expectedValue: gap.requiredKmToDate,
                        gapFloor: GoalVerdictBuilder.kmGapFloor,
                        showsPill: true,
                        accentColor: themeManager.primaryAccentColor
                    )
                }
                // Longest session (max metric): achieved badge once met, plain bar otherwise.
                if let session = periResult?.milestoneItems.first(where: { $0.label == "Langste sessie" }) {
                    if session.isMet {
                        AchievedRow(
                            label: "Langste sessie",
                            requiredValue: String(format: "%.0f", session.required),
                            currentValue: String(format: "%.0f", session.current),
                            accentColor: themeManager.primaryAccentColor
                        )
                    } else {
                        ProgressRow(
                            icon: "ruler",
                            label: "Langste sessie",
                            valueCurrent: String(format: "%.0f", session.current),
                            valueTarget: String(format: "%.0f", session.required),
                            unit: "km",
                            progress: session.progress,
                            reference: nil,
                            actualValue: session.current,
                            expectedValue: 0,
                            gapFloor: 0,
                            showsPill: false,
                            accentColor: themeManager.primaryAccentColor
                        )
                    }
                }
            }
            .padding(4)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if showsLegend {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color(.secondaryLabel).opacity(0.5))
                        .frame(width: 2, height: 10)
                    Text("De streep markeert waar je vandaag zou moeten zijn.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
    }
}

/// Shared 24pt rounded icon tile used by both `ProgressRow` and `AchievedRow`.
private func metricIconTile(_ systemName: String, background: Color, foreground: Color) -> some View {
    RoundedRectangle(cornerRadius: 7)
        .fill(background)
        .frame(width: 24, height: 24)
        .overlay(
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(foreground)
        )
}

// MARK: - ProgressRow

private struct ProgressRow: View {
    let icon: String
    let label: String
    let valueCurrent: String
    let valueTarget: String
    let unit: String
    let progress: Double
    let reference: Double?
    /// Raw (non-percentage) actual value, fed into `GoalVerdictBuilder.paceStatus`
    /// so this row's pill/bar colour can never disagree with the verdict banner.
    let actualValue: Double
    let expectedValue: Double
    /// Absolute dead-band for this metric (GoalVerdictBuilder.trimpGapFloor / kmGapFloor),
    /// so the pill uses exactly the same thresholds as the verdict banner (§1: a gap smaller
    /// than one easy session is not a deviation).
    let gapFloor: Double
    /// The max-metric row (longest session, not-yet-met) has no "expected today" concept,
    /// so it hides the pace pill entirely rather than showing a misleading "on pace".
    let showsPill: Bool
    let accentColor: Color

    private var paceStatus: MetricPaceStatus {
        GoalVerdictBuilder.paceStatus(actual: actualValue, expectedToDate: expectedValue,
                                      absoluteGapFloor: gapFloor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                metricIconTile(icon, background: Color(.systemFill), foreground: .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    // Epic #37 story 37.1c: `label` is a String passed by the caller, resolved
                    // via the catalog. valueCurrent/valueTarget/unit stay verbatim (data + units).
                    Text(LocalizedStringKey(label))
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(.primary)
                    if showsPill {
                        statusPill
                    }
                }

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(valueCurrent)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    // §13: value + unit is data, not copy — render verbatim, no catalog key.
                    Text(verbatim: "/ \(valueTarget) \(unit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(paceStatus == .behind ? Color.orange : accentColor)
                        .frame(width: geo.size.width * min(1, progress), height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                    // Ghost reference marker
                    if let ref = reference, ref > 0 {
                        Rectangle()
                            .fill(Color(.secondaryLabel).opacity(0.5))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * min(1, ref) - 1)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch paceStatus {
        case .onPace, .ahead:
            // "schema" wording, never "tempo/pace" — in a running app that reads as min/km.
            pill(text: paceStatus == .ahead ? "Voor op schema" : "Op schema", color: accentColor)
        case .behind:
            pill(text: "Iets achter", color: .orange)
        }
    }

    private func pill(text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - AchievedRow

/// A max-metric row once its target is met: check badge instead of a progress bar
/// (the redesign's "no anxiety bar once achieved" — see goals-redesign.html AchievedRow).
private struct AchievedRow: View {
    let label: String
    let requiredValue: String
    let currentValue: String
    let accentColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            metricIconTile("ruler", background: accentColor.opacity(0.15), foreground: accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(String(localized: "Doel ≥ \(requiredValue) km"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // §13: value + unit is data, not copy — render verbatim, no catalog key.
            Text(verbatim: "\(currentValue) km")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Circle()
                .fill(accentColor)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )
        }
        .padding(12)
    }
}
