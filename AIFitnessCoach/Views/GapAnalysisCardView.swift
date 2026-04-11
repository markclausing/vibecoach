import SwiftUI
import SwiftData

// MARK: - Epic 23 Sprint 1: Gap Analysis UI Component

/// Kaart die de achterstand of voorsprong t.o.v. de Blueprint laat zien voor één doel.
/// Toont TRIMP-voortgang en afstandsvoortgang als ringvormige of lineaire meter.
struct GapAnalysisCardView: View {
    let gap: BlueprintGap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header: doelnaam + blueprint-type badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.goal.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(gap.blueprintType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                weeksRemainingBadge
            }

            Divider()

            // TRIMP voortgangsrij
            progressRow(
                icon: "bolt.fill",
                iconColor: trimpIconColor,
                label: "Trainingsbelasting (TRIMP)",
                progress: gap.trimpProgressPct,
                progressColor: trimpBarColor,
                statusLine: gap.trimpStatusLine
            )

            // Afstandsvoortgangsrij (alleen voor doelen met een km-target > 0)
            if gap.requiredKmToDate > 0 {
                progressRow(
                    icon: distanceIcon,
                    iconColor: kmIconColor,
                    label: "Afstand (\(gap.blueprintType == .cyclingTour ? "km fietsen" : "km hardlopen"))",
                    progress: gap.kmProgressPct,
                    progressColor: kmBarColor,
                    statusLine: gap.kmStatusLine ?? ""
                )
            }

            // Bijsturingsbericht als de atleet significant achterstaat
            if gap.isBehindOnTRIMP || gap.isBehindOnKm {
                catchUpBanner
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sub-views

    private var weeksRemainingBadge: some View {
        let weeks = Int(gap.weeksRemaining)
        return Text("\(weeks)w")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }

    private func progressRow(icon: String, iconColor: Color, label: String, progress: Double, progressColor: Color, statusLine: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(progressColor)
            }
            // Voortgangsbalk
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * min(1.0, progress), height: 8)
                        .animation(.easeOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
            // Status tekst
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var catchUpBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bijsturing nodig")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                // Bereken hoeveel extra volume per week nodig is
                if gap.isBehindOnTRIMP, gap.weeksRemaining > 0 {
                    let extra = Int((gap.trimpGap / gap.weeksRemaining).rounded())
                    Text("Circa \(extra) extra TRIMP/week om op schema te komen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if gap.isBehindOnKm, gap.requiredKmToDate > 0, gap.weeksRemaining > 0 {
                    let extra = String(format: "%.0f", gap.kmGap / gap.weeksRemaining)
                    Text("Circa \(extra) extra km/week voor het afstandsschema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Kleurberekeningen

    private var trimpBarColor: Color {
        switch gap.trimpProgressPct {
        case 0.9...:   return .green
        case 0.6..<0.9: return .orange
        default:        return .red
        }
    }

    private var trimpIconColor: Color { trimpBarColor }

    private var kmBarColor: Color {
        switch gap.kmProgressPct {
        case 0.9...:   return .green
        case 0.6..<0.9: return .orange
        default:        return .red
        }
    }

    private var kmIconColor: Color { kmBarColor }

    private var distanceIcon: String {
        gap.blueprintType == .cyclingTour ? "bicycle" : "figure.run"
    }
}

// MARK: - Sectie voor de Doelen tab: alle gaps tegelijk

/// Sectiehoedje voor de Gap Analysis kaarten in de Doelen-tab.
/// Toont alle actieve doelen met hun TRIMP/km-voortgang.
struct GapAnalysisSectionView: View {
    let gaps: [BlueprintGap]

    var body: some View {
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.blue)
                    Text("Blueprint Voortgang")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)

                ForEach(gaps, id: \.goal.id) { gap in
                    GapAnalysisCardView(gap: gap)
                        .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }
}
