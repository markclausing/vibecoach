import SwiftUI

// Epic #65 story 65.5: split out of WeekTimelineView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - DayCircleView

struct DayCircleView: View {
    let date: Date
    let workout: SuggestedWorkout?
    let hasActivity: Bool
    let isRest: Bool
    /// Epic #55 story 55.2: 1-based stage number when this day is a multi-day event day.
    var stageIndex: Int?

    @EnvironmentObject var themeManager: ThemeManager

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: Date()) }
    private var isCompleted: Bool { isPast && hasActivity }
    private var isStage: Bool { stageIndex != nil }

    private var dayAbbrev: String {
        let f = AppDateFormatters.display("EEE")
        return f.string(from: date).prefix(2).uppercased()
    }
    private var dayNumber: String {
        return AppDateFormatters.display("d").string(from: date)
    }

    private var subIcon: String {
        if isStage { return "flag.checkered" }
        if isRest { return "moon.fill" }
        guard let w = workout else { return "minus" }
        switch w.kind {
        case .interval: return "bolt.fill"
        case .strength: return "dumbbell.fill"
        default:        return "waveform.path.ecg"
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(dayAbbrev)
                .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)

            ZStack {
                if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeManager.primaryAccentColor, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                }
                Circle()
                    .fill(isToday
                          ? themeManager.primaryAccentColor
                          : (isCompleted ? themeManager.primaryAccentColor.opacity(0.12) : Color(.systemBackground)))
                    .overlay(Circle().stroke(isToday || isCompleted ? Color.clear : Color(.systemGray4), lineWidth: 1))
                    .frame(width: 34, height: 34)

                if isCompleted && !isToday {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(themeManager.primaryAccentColor)
                } else {
                    Text(dayNumber)
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .white : (isPast ? .secondary : .primary))
                }
            }
            .frame(width: 38, height: 38)

            Image(systemName: subIcon)
                .font(.system(size: 9))
                .foregroundColor(isStage
                                 ? themeManager.primaryAccentColor
                                 : (isRest ? .secondary : (isToday ? themeManager.primaryAccentColor : .secondary)))
        }
    }
}
