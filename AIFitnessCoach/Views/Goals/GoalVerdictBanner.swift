import SwiftUI

/// Epic #72 story 72.2: the "will I make it?" banner on the goal hero card.
/// Renders a GoalVerdict (built by GoalVerdictBuilder) as tone icon + headline + one
/// composed sentence. Tone colours follow the house palette: accent / orange / red.
struct GoalVerdictBanner: View {
    let verdict: GoalVerdict
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(toneColor)
                    .frame(width: 24, height: 24)
                Image(systemName: toneIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                headline
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(toneColor)
                Text(bodySentence)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(toneColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tone

    private var toneIcon: String {
        switch verdict.tone {
        case .onTrack:        return "checkmark"
        case .slightlyBehind: return "clock"
        case .atRisk:         return "exclamationmark"
        }
    }

    private var toneColor: Color {
        switch verdict.tone {
        case .onTrack:        return themeManager.primaryAccentColor
        case .slightlyBehind: return .orange
        case .atRisk:         return .red
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch verdict.tone {
        case .onTrack:        Text("Op koers")
        case .slightlyBehind: Text("Iets achter op schema")
        case .atRisk:         Text("Bijsturing nodig")
        }
    }

    // MARK: - Body sentence
    // Epic #37 §13: numbers pre-formatted as String and interpolated as %@, never %lld.

    private var bodySentence: String {
        verdict.facts.map(sentence(for:)).joined(separator: " ")
    }

    private func sentence(for fact: GoalVerdict.Fact) -> String {
        switch fact {
        case .weekContext(let week, let totalWeeks):
            let wStr = "\(week)"
            let tStr = "\(totalWeeks)"
            return String(localized: "Het is week \(wStr) van \(tStr).")
        case .milestoneAchieved(let label):
            let localizedLabel = String(localized: String.LocalizationValue(label))
            return String(localized: "Mijlpaal '\(localizedLabel)' is al gehaald.")
        case .loadOnPace:
            return String(localized: "Trainingsbelasting ligt op schema.")
        case .loadAhead:
            return String(localized: "Trainingsbelasting ligt voor op schema.")
        case .loadBehind(let delta):
            let dStr = "\(delta)"
            return String(localized: "Trainingsbelasting ligt \(dStr) TRIMP achter.")
        case .distanceOnPace:
            return String(localized: "Afstand ligt op schema.")
        case .distanceAhead:
            return String(localized: "Afstand ligt voor op schema.")
        case .distanceSlightlyBehind(let delta):
            let dStr = "\(delta)"
            return String(localized: "Geef je afstand een zetje — \(dStr) km achter op schema.")
        case .offTrack(let current, let required):
            let cStr = "\(current)"
            let rStr = "\(required)"
            return String(localized: "Je traint nu \(cStr) TRIMP/week, terwijl \(rStr) nodig is.")
        case .taperingOverload:
            return String(localized: "Je belasting is te hoog voor de taper — bouw af.")
        }
    }
}
