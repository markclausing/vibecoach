import SwiftUI

/// V2.0 Sprint 1: Vernieuwde Vibe Score kaart met geïntegreerde metrics-grid en coach-hint balk.
/// Vervangt de oude VibeScoreCardView met een card-first layout:
///   Top → tinted score + status
///   Midden → HRV / SLAAP / RUST-HR rij
///   Onderin → coach-hint met actie-link (optioneel)
struct VibeScoreCardV2: View {
    let readiness: DailyReadiness?
    var isLoading: Bool = false
    var isUnavailable: Bool = false
    var injuryRiskLevel: DashboardView.InjuryRiskLevel = .safe
    var todayWorkoutName: String? = nil
    var onAskWhy: (() -> Void)? = nil
    /// Live rusthartslag direct vanuit HealthKit — overschrijft de opgeslagen waarde in readiness.
    var liveRestingHeartRate: Double? = nil
    /// Live VO₂max direct vanuit HealthKit.
    var liveVO2Max: Double? = nil

    @EnvironmentObject var themeManager: ThemeManager

    private var scoreColor: Color {
        if isUnavailable { return Color(red: 0.3, green: 0.6, blue: 0.9) }
        guard let r = readiness else { return .gray }
        if r.readinessScore >= 80 { return themeManager.primaryAccentColor }
        if r.readinessScore >= 50 { return .orange }
        return .red
    }

    private var statusTitle: String {
        if isLoading { return "Berekenen..." }
        if isUnavailable { return "Vibe Score op pauze" }
        guard let r = readiness else { return "Geen data" }
        switch injuryRiskLevel {
        case .risk:    return "Voorzichtig — Blessurerisico"
        case .caution: return "Let op — Actieve Klachten"
        case .safe:
            if r.readinessScore >= 80 { return "Optimaal hersteld" }
            if r.readinessScore >= 50 { return "Matig hersteld" }
            return "Focus op herstel"
        }
    }

    private var statusDescription: String {
        if isUnavailable { return "Geen recente Watch-data. Baseer je dag op je gevoel." }
        guard let r = readiness else { return "" }
        let hrv = Int(r.hrv)
        if r.readinessScore >= 80 { return "HRV \(hrv) ms boven baseline. Goede dag voor intensiteit." }
        if r.readinessScore >= 50 { return "HRV \(hrv) ms. Houd de intensiteit gematigd." }
        return "HRV \(hrv) ms. Prioriteit: rust en herstel."
    }

    private func formatSleepMain(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)u \(m)"
    }

    private func sleepQualityLabel(_ hours: Double) -> String {
        if hours >= 8 { return "uitstekend" }
        if hours >= 7 { return "goed" }
        if hours >= 6 { return "matig" }
        return "te kort"
    }

    var body: some View {
        VStack(spacing: 0) {
            topSection
            Divider()
            metricsSection
            if let name = todayWorkoutName {
                Divider()
                coachHintSection(workoutName: name)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)
        .accessibilityIdentifier("VibeScoreCard")
    }

    // MARK: - Subsecties

    private var topSection: some View {
        HStack(spacing: 16) {
            scoreCircle
            VStack(alignment: .leading, spacing: 4) {
                Text("VIBE SCORE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .kerning(0.8)
                Text(statusTitle)
                    .font(.headline)
                    .foregroundColor(injuryRiskLevel == .safe ? .primary : .orange)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.9)
            }
            Spacer()
        }
        .padding(16)
        .background(scoreColor.opacity(isUnavailable ? 0.05 : 0.10))
    }

    private var scoreCircle: some View {
        ZStack {
            Circle()
                .stroke(scoreColor.opacity(0.20), lineWidth: 5)
            if !isLoading, let r = readiness {
                Circle()
                    .trim(from: 0, to: CGFloat(r.readinessScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(readiness != nil ? "\(readiness!.readinessScore)" : "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
        .frame(width: 68, height: 68)
    }

    private var metricsSection: some View {
        HStack(spacing: 0) {
            MetricColumnV2(
                label: "HRV",
                value: readiness.map { String(format: "%.0f", $0.hrv) } ?? "--",
                unit: "ms",
                detail: nil
            )
            Divider().frame(height: 48)
            MetricColumnV2(
                label: "SLAAP",
                value: readiness.map { formatSleepMain($0.sleepHours) } ?? "--",
                unit: "min",
                detail: readiness.map { sleepQualityLabel($0.sleepHours) }
            )
            Divider().frame(height: 48)
            MetricColumnV2(
                label: "RUST-HR",
                value: (liveRestingHeartRate ?? readiness?.restingHeartRate).map { String(format: "%.0f", $0) } ?? "--",
                unit: "bpm",
                detail: nil
            )
            Divider().frame(height: 48)
            MetricColumnV2(
                label: "VO₂MAX",
                value: liveVO2Max.map { String(format: "%.0f", $0) } ?? "--",
                unit: "ml/kg",
                detail: nil
            )
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }

    private func coachHintSection(workoutName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundColor(themeManager.primaryAccentColor)
            Text("Ik houd vast aan je **\(workoutName)**")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button {
                onAskWhy?()
            } label: {
                Text("Vraag waarom ›")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.primaryAccentColor)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
    }
}

// MARK: - Metric kolom

private struct MetricColumnV2: View {
    let label: String
    let value: String
    let unit: String
    let detail: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .kerning(0.5)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let d = detail {
                Text(d)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
