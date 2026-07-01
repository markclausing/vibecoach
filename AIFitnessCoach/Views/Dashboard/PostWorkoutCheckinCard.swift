import SwiftUI
import SwiftData

// MARK: - EPIC 18: Post-Workout Check-in Configuration

/// Sprint 19: Central threshold values for the RPE check-in.
/// Always use these constants instead of loose magic numbers across the codebase.
enum WorkoutCheckinConfig {
    /// Minimum duration (seconds) to consider a workout a 'real training' — 15 minutes.
    static let minimumDurationSeconds = 900
    /// Minimum TRIMP for a 'real training'; filters out commutes and short walks.
    static let minimumTRIMP: Double = 15
    /// Sentinel value for 'ignored': falls outside the valid RPE scale (1–10) and marks
    /// that the user deliberately labelled the activity as not a training.
    static let ignoredRPESentinel = 0
}

// MARK: - EPIC 18 / 57: Post-Workout Check-in Card

/// One holistic post-workout feedback choice (Epic #57). Each option maps to an
/// (rpe, mood) pair persisted on `ActivityRecord`, so the coach prompt,
/// `LastWorkoutContextFormatter` and `SessionType.expectedRPERange` keep working on the
/// stored `Int` — no schema migration, no prompt change. The talk-test descriptions make
/// "what do I pick" obvious; one tap saves. The numeric values still land in the four
/// downstream RPE buckets (light 1–3 / moderate 4–6 / hard 7–8 / maximal 9–10), and the
/// 8/9 values keep triggering the low-TRIMP-vs-high-RPE overtraining check.
private struct WorkoutCheckinOption: Identifiable {
    let id: String
    let icon: String
    let label: LocalizedStringKey
    let detail: LocalizedStringKey
    let rpe: Int
    /// Existing mood SF Symbol name, kept verbatim for downstream compatibility.
    let mood: String
    let color: Color

    static let all: [WorkoutCheckinOption] = [
        WorkoutCheckinOption(id: "easy", icon: "leaf.fill",
            label: "Makkelijk", detail: "Kon makkelijk doorpraten",
            rpe: 2, mood: "checkmark.circle.fill", color: .green),
        WorkoutCheckinOption(id: "good", icon: "hand.thumbsup.fill",
            label: "Lekker gewerkt", detail: "Stevig, maar voelde goed",
            rpe: 5, mood: "bolt.fill", color: Color(red: 0.85, green: 0.65, blue: 0.13)),
        WorkoutCheckinOption(id: "hard", icon: "flame.fill",
            label: "Zwaar", detail: "Flink afgezien, praten lukte amper",
            rpe: 8, mood: "zzz", color: Color(red: 0.88, green: 0.58, blue: 0.32)),
        WorkoutCheckinOption(id: "empty", icon: "zzz",
            label: "Leeg / uitgeput", detail: "Kon echt niet meer",
            rpe: 9, mood: "zzz", color: .red),
        WorkoutCheckinOption(id: "pain", icon: "bandage.fill",
            label: "Pijn / klacht", detail: "Er deed iets zeer",
            rpe: 5, mood: "bandage.fill", color: .pink)
    ]
}

/// Card that appears when the most recent real workout (≤48h, ≥15 min, TRIMP ≥15) still has no RPE.
/// Epic #57: the user picks one holistic option (effort + feel combined); one tap saves and the
/// card disappears immediately. rpe == 0 is used as a sentinel for 'Ignored' (not a training).
struct PostWorkoutCheckinCard: View {
    @Bindable var activity: ActivityRecord
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager

    /// Callback so DashboardView can update the AI cache immediately after saving.
    /// rpe == 0 means ignored — the caller does not store this as real feedback.
    var onSaved: ((Int, String) -> Void)?

    /// Format the subtitle: '[Sport name] • [Duration] min • [Today/Yesterday]'
    private var subtitle: String {
        let sport = activity.sportCategory.displayName
        let durationMin = activity.movingTime / 60
        let calendar = Calendar.current
        let relativeDay: String
        if calendar.isDateInToday(activity.startDate) {
            relativeDay = String(localized: "Vandaag")
        } else if calendar.isDateInYesterday(activity.startDate) {
            relativeDay = String(localized: "Gisteren")
        } else {
            relativeDay = AppDateFormatters.display("d MMM").string(from: activity.startDate)
        }
        return "\(sport) • \(durationMin) min • \(relativeDay)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with ignore button at the top right
            HStack(alignment: .top) {
                Image(systemName: "checkmark.bubble.fill")
                    .foregroundStyle(themeManager.primaryAccentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoe ging je laatste training?")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: ignoreActivity) {
                    Text("Negeer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Epic #57: one tap on a holistic option (effort + feel combined) saves immediately.
            VStack(spacing: 8) {
                ForEach(WorkoutCheckinOption.all) { option in
                    Button(action: { saveFeedback(option) }) {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(option.color)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    // Fixed dark text: the option cards use a white background
                                    // (below), so .primary would vanish in dark mode.
                                    .foregroundColor(.black)
                                Text(option.detail)
                                    .font(.caption2)
                                    .foregroundColor(Color(white: 0.45))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(white: 0.6))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // White card with a soft drop shadow so each option reads as a
                        // distinct, tappable element against the card's material background.
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("RPEOption_\(option.id)")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .accessibilityIdentifier("RPECheckinCard")
    }

    private func saveFeedback(_ option: WorkoutCheckinOption) {
        activity.rpe = option.rpe
        activity.mood = option.mood
        try? modelContext.save()
        onSaved?(option.rpe, option.mood)
    }

    /// Marks the activity as 'not a training' via the sentinel value from WorkoutCheckinConfig.
    /// The card disappears immediately; onSaved is not called so the AI cache stays unchanged.
    private func ignoreActivity() {
        activity.rpe = WorkoutCheckinConfig.ignoredRPESentinel
        try? modelContext.save()
    }
}
