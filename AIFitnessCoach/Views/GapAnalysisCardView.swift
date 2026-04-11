import SwiftUI
import SwiftData

// MARK: - Epic 23 Sprint 1 & 2: Gap Analysis + Future Projection UI

/// Kaart die de cumulatieve achterstand/voorsprong binnen de huidige trainingsfase toont,
/// aangevuld met een toekomstprognose ("Glazen Bol") uit de FutureProjectionService.
struct GapAnalysisCardView: View {
    let gap: BlueprintGap
    /// Optionele prognose voor hetzelfde doel. Nil als er geen blueprint-match is.
    var projection: GoalProjection? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header: doelnaam + weken resterend
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.goal.title)
                        .font(.headline)
                        .lineLimit(1)
                    // Fase + week-context: "Build Phase (Week 3/8)"
                    Text(gap.phaseProgressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                weeksRemainingBadge
            }

            Divider()

            // TRIMP voortgangsrij met ghost marker
            phaseProgressRow(
                icon: "bolt.fill",
                label: "Trainingsbelasting (TRIMP)",
                actualPct: gap.trimpProgressPct,
                referencePct: gap.trimpReferencePct,
                statusLine: gap.trimpStatusLine
            )

            // Km voortgangsrij met ghost marker (alleen als er een km-target is)
            if gap.totalPhaseKmTarget > 0 {
                phaseProgressRow(
                    icon: distanceIcon,
                    label: "Afstand (\(gap.blueprintType == .cyclingTour ? "fietsen" : "hardlopen"))",
                    actualPct: gap.kmProgressPct,
                    referencePct: gap.kmReferencePct,
                    statusLine: gap.kmStatusLine ?? ""
                )
            }

            // Bijsturingsbanner
            if gap.isBehindOnTRIMP || gap.isBehindOnKm {
                catchUpBanner
            }

            // MARK: Prognose-sectie (Sprint 23.2)
            if let projection {
                Divider()
                projectionSection(projection)
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

    /// Voortgangsrij met gekleurde balk + ghost marker op de verwachte positie.
    ///
    /// - `actualPct`:    hoeveel van het fase-totaal je hebt behaald (0.0–1.0)
    /// - `referencePct`: waar je vandaag volgens de Blueprint zou moeten staan (0.0–1.0)
    private func phaseProgressRow(
        icon: String,
        label: String,
        actualPct: Double,
        referencePct: Double,
        statusLine: String
    ) -> some View {
        let barColor = progressColor(for: actualPct, reference: referencePct)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(barColor)
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", actualPct * 100))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(barColor)
            }

            // Voortgangsbalk + ghost marker
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {

                    // Achtergrond
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 10)

                    // Gekleurde voortgangsbalk
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.gradient)
                        .frame(width: width * min(1.0, actualPct), height: 10)
                        .animation(.easeOut(duration: 0.6), value: actualPct)

                    // Ghost marker — de "Reference" streep
                    // Een dun wit lijntje + driehoekje boven de balk
                    let ghostX = width * min(1.0, referencePct)
                    ghostMarker(at: ghostX)
                        .animation(.easeOut(duration: 0.6), value: referencePct)
                }
            }
            .frame(height: 18) // Iets hoger voor de driehoek

            // Status tekst
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Bouwt de ghost marker: een smal wit lijntje + klein driehoekje erboven.
    @ViewBuilder
    private func ghostMarker(at x: CGFloat) -> some View {
        // Verticale streep
        Rectangle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 2, height: 10)
            .offset(x: x - 1)

        // Driehoekje boven de balk
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .offset(x: x - 4, y: -9)
    }

    private var catchUpBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bijsturing nodig")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                // TRIMP-bijsturing: vertaald naar concrete duur via TRIMPTranslator
                if let hint = gap.catchUpHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Km-bijsturing
                if gap.isBehindOnKm, gap.totalPhaseKmTarget > 0, gap.weeksRemaining > 0 {
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

    // MARK: - Prognose sectie (Sprint 23.2 — Glazen Bol)

    @ViewBuilder
    private func projectionSection(_ projection: GoalProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            // Sectietitel
            HStack(spacing: 6) {
                Image(systemName: "crystal.ball.fill")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                Text("Prognose")
                    .font(.subheadline.weight(.semibold))
            }

            // Datum-vergelijking: gepland vs. verwacht
            HStack(spacing: 0) {
                dateColumn(
                    label: "Gepland",
                    date: projection.plannedPeakDate,
                    color: .blue
                )
                Spacer()
                statusBadge(projection)
                Spacer()
                dateColumn(
                    label: "Verwacht",
                    date: projection.projectedPeakDate ?? projection.plannedPeakDate,
                    color: statusSwiftColor(projection.status)
                )
            }

            // Uitlegzin
            Text(projectionCaption(projection))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dateColumn(label: String, date: Date, color: Color) -> some View {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = Locale(identifier: "nl_NL")
        return VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(df.string(from: date))
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func statusBadge(_ projection: GoalProjection) -> some View {
        let color = statusSwiftColor(projection.status)
        return VStack(spacing: 3) {
            Image(systemName: projection.status.icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(projection.status.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
        }
    }

    /// Vertaalt de ProjectionStatus naar een SwiftUI Color.
    private func statusSwiftColor(_ status: ProjectionStatus) -> Color {
        switch status {
        case .alreadyPeaking, .onTrack: return .green
        case .atRisk:                   return .orange
        case .unreachable:              return .red
        }
    }

    /// Leesbare uitlegzin onder de datum-rij.
    private func projectionCaption(_ projection: GoalProjection) -> String {
        let pct = Int((projection.observedGrowthRate * 100).rounded())
        switch projection.status {
        case .alreadyPeaking:
            return "Je piekbelasting is al bereikt. Vasthouden en binnenkort beginnen met taperen."
        case .onTrack:
            let weeks = Int(abs(projection.weeksDelta).rounded())
            return "Op basis van \(pct)% groei/week ben je \(weeks) week(en) eerder klaar dan gepland. Goed bezig!"
        case .atRisk:
            let weeks = Int(abs(projection.weeksDelta).rounded())
            return "Je groeit \(pct)% per week. Je loopt \(weeks) week(en) achter op de geplande piekdatum. Schroef het volume op."
        case .unreachable:
            return "Zelfs met 10% groei per week is de piekbelasting niet haalbaar vóór de racedag. Bespreek dit met je coach."
        }
    }

    // MARK: - Kleurlogica

    /// Kleur op basis van hoe dicht je bij de ghost marker zit.
    /// Groen = boven/op target, oranje = licht achter, rood = significant achter.
    private func progressColor(for actual: Double, reference: Double) -> Color {
        guard reference > 0 else { return .green }
        let ratio = actual / reference  // 1.0 = precies op schema
        switch ratio {
        case 0.9...:   return .green
        case 0.7..<0.9: return .orange
        default:        return .red
        }
    }

    private var distanceIcon: String {
        gap.blueprintType == .cyclingTour ? "bicycle" : "figure.run"
    }
}

// MARK: - Sectie in de Doelen-tab

struct GapAnalysisSectionView: View {
    let gaps: [BlueprintGap]
    /// Projecties gematcht op goal.id. Wordt doorgegeven vanuit GoalsListView.
    var projections: [GoalProjection] = []

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
                    let projection = projections.first { $0.goal.id == gap.goal.id }
                    GapAnalysisCardView(gap: gap, projection: projection)
                        .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }
}
