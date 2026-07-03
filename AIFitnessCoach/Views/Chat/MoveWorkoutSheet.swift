import SwiftUI

// MARK: - Story 33.2a: Move sheet with day chips

/// Compact sheet that shows seven day chips for the current week (Mon → Sun).
/// Tap on a chip → callback with the chosen `Date`. Fits the Serene style: soft
/// colors, capsule shape, one primary interaction. No DatePicker (too busy).
struct MoveWorkoutSheet: View {
    let workout: SuggestedWorkout
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    /// Generates Monday through Sunday of the current week.
    private var weekDays: [Date] {
        let calendar = Calendar(identifier: .iso8601) // Monday as first day
        let today = calendar.startOfDay(for: Date())
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return [today]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekInterval.start) }
    }

    private var selectedDate: Date {
        Calendar.current.startOfDay(for: workout.displayDate)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Kies een nieuwe dag deze week. De coach respecteert je keuze in volgende suggesties.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(weekDays, id: \.self) { day in
                            dayChip(for: day)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Verplaats sessie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleer") { dismiss() }
                }
            }
        }
    }

    private func dayChip(for day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let formatter = AppDateFormatters.display("EEE")
        let weekday = formatter.string(from: day).prefix(1).uppercased() + formatter.string(from: day).dropFirst()
        let dayNumber = Calendar.current.component(.day, from: day)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.caption2).fontWeight(.semibold)
                Text("\(dayNumber)")
                    .font(.title3).fontWeight(.bold)
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : themeManager.primaryAccentColor)
            .frame(width: 56, height: 72)
            .background(isSelected ? themeManager.primaryAccentColor : themeManager.primaryAccentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
