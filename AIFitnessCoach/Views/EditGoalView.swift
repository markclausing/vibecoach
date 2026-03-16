import SwiftUI
import SwiftData

struct EditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var goal: FitnessGoal

    let sportTypes = ["Hardlopen", "Wielrennen", "Zwemmen", "Krachttraining", "Triatlon", "Anders"]

    // Tijdelijke state vars, we assignen aan 'goal' on the fly in een Form, of bij "Opslaan"
    // Bindable is mooi, we werken direct op het object.

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
                Picker("Sport", selection: Binding(
                    get: { goal.sportType ?? "" },
                    set: { goal.sportType = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Selecteer een sport").tag("")
                    ForEach(sportTypes, id: \.self) { sport in
                        Text(sport).tag(sport)
                    }
                }
            }

            Section(header: Text("Status")) {
                Toggle("Doel Behaald", isOn: $goal.isCompleted)
                DatePicker("Streefdatum", selection: $goal.targetDate, displayedComponents: .date)
            }
        }
        .navigationTitle("Bewerk Doel")
        .navigationBarTitleDisplayMode(.inline)
        // Auto-save on dismiss is standard behaviour voor @Bindable in SwiftData
    }
}
