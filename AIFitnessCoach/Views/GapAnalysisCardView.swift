import SwiftUI
import SwiftData

// MARK: - Epic 23 Sprint 1 & 2: Gap Analysis + Future Projection UI

/// Card that shows the cumulative deficit/surplus within the current training phase.
///
/// - `isEmbedded`: use `true` when the card sits inside a `GoalDetailContainer` —
///   this hides the goal-title header and its own background (the container already has those).
struct GapAnalysisCardView: View {
    let gap: BlueprintGap
    /// Optional projection — only shown when `isEmbedded == false` (standalone use).
    var projection: GoalProjection?
    /// True = no own header/background; the container provides the context.
    var isEmbedded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header: only show outside a GoalDetailContainer
            if !isEmbedded {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gap.goal.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(gap.phaseProgressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    weeksRemainingBadge
                }
                Divider()
            }

            // Phase-context label (always visible — also when embedded)
            Text(gap.phaseProgressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            // TRIMP progress row with ghost marker
            phaseProgressRow(
                icon: "bolt.fill",
                label: "Trainingsbelasting (TRIMP)",
                actualPct: gap.trimpProgressPct,
                referencePct: gap.trimpReferencePct,
                statusLine: gap.trimpStatusLine
            )

            // Km progress row with ghost marker (only if there is a km target)
            if gap.totalPhaseKmTarget > 0 {
                phaseProgressRow(
                    icon: distanceIcon,
                    label: "Afstand (\(gap.blueprintType == .cyclingTour ? "fietsen" : "hardlopen"))",
                    actualPct: gap.kmProgressPct,
                    referencePct: gap.kmReferencePct,
                    statusLine: gap.kmStatusLine ?? ""
                )
            }

            // Corrective banner
            if gap.isBehindOnTRIMP || gap.isBehindOnKm {
                catchUpBanner
            }

            // Projection section only outside the container (embedded shows this separately already)
            if !isEmbedded, let projection {
                Divider()
                projectionSection(projection)
            }
        }
        .padding(isEmbedded ? 0 : 16)
        .background(isEmbedded ? Color.clear : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: isEmbedded ? 0 : 14))
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

    /// Progress row with a colored bar + ghost marker at the expected position.
    ///
    /// - `actualPct`:    how much of the phase total you have achieved (0.0–1.0)
    /// - `referencePct`: where you should be today according to the Blueprint (0.0–1.0)
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

            // Progress bar + ghost marker
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {

                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 10)

                    // Colored progress bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.gradient)
                        .frame(width: width * min(1.0, actualPct), height: 10)
                        .animation(.easeOut(duration: 0.6), value: actualPct)

                    // Ghost marker — the "Reference" line
                    // A thin white line + small triangle above the bar
                    let ghostX = width * min(1.0, referencePct)
                    ghostMarker(at: ghostX)
                        .animation(.easeOut(duration: 0.6), value: referencePct)
                }
            }
            .frame(height: 18) // Slightly taller to fit the triangle

            // Status text
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Builds the ghost marker: a narrow white line + small triangle above it.
    @ViewBuilder
    private func ghostMarker(at x: CGFloat) -> some View {
        // Vertical line
        Rectangle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 2, height: 10)
            .offset(x: x - 1)

        // Small triangle above the bar
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

                // TRIMP correction: translated to a concrete duration via TRIMPTranslator
                if let hint = gap.catchUpHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Km correction
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

    // MARK: - Projection section (Sprint 23.2 — Crystal Ball)

    @ViewBuilder
    private func projectionSection(_ projection: GoalProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            // Section title
            HStack(spacing: 6) {
                Image(systemName: "crystal.ball.fill")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                Text("Prognose")
                    .font(.subheadline.weight(.semibold))
            }

            // Date comparison: planned vs. expected
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

            // Explanatory sentence
            Text(projectionCaption(projection))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dateColumn(label: String, date: Date, color: Color) -> some View {
        let df = AppDateFormatters.display("d MMM")
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

    /// Translates the ProjectionStatus to a SwiftUI Color.
    private func statusSwiftColor(_ status: ProjectionStatus) -> Color {
        switch status {
        case .alreadyPeaking, .onTrack:    return .green
        case .atRisk, .catchUpNeeded:      return .orange
        case .unreachable:                 return .red
        }
    }

    /// Readable explanatory sentence below the date row.
    /// Epic #37 story 37.1c: rendered via Text(projectionCaption(...)) -> verbatim. Resolve via the
    /// String Catalog. The percentage is pre-formatted into a String and interpolated as %@ to keep
    /// a literal "%" out of the generated format key.
    private func projectionCaption(_ projection: GoalProjection) -> String {
        let pct = Int((projection.observedGrowthRate * 100).rounded())
        let pctStr = "\(pct)%"
        switch projection.status {
        case .alreadyPeaking:
            return String(localized: "Je piekbelasting is al bereikt. Vasthouden en binnenkort beginnen met taperen.")
        case .onTrack:
            let weeks = Int(abs(projection.weeksDelta).rounded())
            return String(localized: "Op basis van \(pctStr) groei/week ben je \(weeks) week(en) eerder klaar dan gepland. Goed bezig!")
        case .atRisk:
            let weeks = Int(abs(projection.weeksDelta).rounded())
            return String(localized: "Je groeit \(pctStr) per week. Je loopt \(weeks) week(en) achter op de geplande piekdatum. Schroef het volume op.")
        case .catchUpNeeded:
            let weeks = Int(abs(projection.weeksDelta).rounded())
            if projection.hasCrossTrainingBonus {
                let sportWord = projection.blueprintType == .cyclingTour ? String(localized: "fiets") : String(localized: "hardloop")
                return String(localized: "Bottleneck: \(sportWord)-volume. Omdat je aerobe basis (TRIMP) sterk is, kunnen we dit gat de komende weken sneller dichten zodra je hersteld bent. Nog \(weeks) week(en) bij te sturen — ruim op tijd.")
            } else {
                return String(localized: "Je loopt \(weeks) week(en) achter, maar de racedag is nog ver genoeg weg voor een gerichte inhaalslag. Stap voor stap opbouwen.")
            }
        case .unreachable:
            return String(localized: "Zelfs met maximale wekelijkse groei is de piekbelasting niet haalbaar vóór de racedag. Bespreek dit met je coach.")
        }
    }

    // MARK: - Color logic

    /// Color based on how close you are to the ghost marker.
    /// Green = at/above target, orange = slightly behind, red = significantly behind.
    private func progressColor(for actual: Double, reference: Double) -> Color {
        guard reference > 0 else { return .green }
        let ratio = actual / reference  // 1.0 = exactly on schedule
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
