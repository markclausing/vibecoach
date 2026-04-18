import SwiftUI
import SwiftData

struct EditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var goal: FitnessGoal

    // Stretch goal: lokale state zodat de DatePicker altijd een geldige Date krijgt
    @State private var hasStretchGoal: Bool
    @State private var stretchGoalPickerDate: Date

    init(goal: FitnessGoal) {
        self.goal = goal
        if let stretchTime = goal.stretchGoalTime, stretchTime > 0 {
            _hasStretchGoal = State(initialValue: true)
            let midnight = Calendar.current.startOfDay(for: Date())
            _stretchGoalPickerDate = State(initialValue: midnight.addingTimeInterval(stretchTime))
        } else {
            _hasStretchGoal = State(initialValue: false)
            _stretchGoalPickerDate = State(initialValue: Calendar.current.startOfDay(for: Date()).addingTimeInterval(3 * 3600))
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Details")) {
                TextField("Titel", text: $goal.title)
                TextField("Extra notities (optioneel)", text: Binding(
                    get: { goal.details ?? "" },
                    set: { goal.details = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }

            Section(header: Text("Type Sport")) {
                Picker("Sport", selection: Binding<SportCategory>(
                    get: { goal.sportCategory ?? .other },
                    set: { goal.sportCategory = $0 }
                )) {
                    ForEach(SportCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
            }

            Section(header: Text("Type Evenement & Intentie")) {
                Picker("Evenement", selection: Binding<EventFormat>(
                    get: { goal.resolvedFormat },
                    set: { goal.format = $0 }
                )) {
                    Text("Eendaagse Race").tag(EventFormat.singleDayRace)
                    Text("Eendaagse Tocht").tag(EventFormat.singleDayTour)
                    Text("Meerdaagse Etappe").tag(EventFormat.multiDayStage)
                }

                Picker("Doel", selection: Binding<PrimaryIntent>(
                    get: { goal.resolvedIntent },
                    set: { goal.intent = $0 }
                )) {
                    Text("Uitlopen / Genieten").tag(PrimaryIntent.completion)
                    Text("Presteren / Zo snel mogelijk").tag(PrimaryIntent.peakPerformance)
                }

                Toggle("Streeftijd instellen", isOn: $hasStretchGoal)

                if hasStretchGoal {
                    DatePicker(
                        "Doeltijd (u:min)",
                        selection: $stretchGoalPickerDate,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section(header: Text("Status")) {
                Toggle("Doel Behaald", isOn: $goal.isCompleted)
                DatePicker("Streefdatum", selection: $goal.targetDate, displayedComponents: .date)
            }
        }
        .navigationTitle("Bewerk Doel")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            goal.stretchGoalTime = hasStretchGoal ? stretchTimeInterval(from: stretchGoalPickerDate) : nil
            try? modelContext.save()
        }
    }

    /// Converteert de uur:minuut-waarde van een Date naar een TimeInterval (seconden).
    private func stretchTimeInterval(from date: Date) -> TimeInterval {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return TimeInterval(h * 3600 + m * 60)
    }
}
