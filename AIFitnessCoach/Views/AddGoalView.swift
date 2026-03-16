import SwiftUI
import SwiftData

struct AddGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var targetDate = Date().addingTimeInterval(86400 * 30) // +30 dagen
    @State private var sportType = ""

    let sportTypes = ["Hardlopen", "Wielrennen", "Zwemmen", "Krachttraining", "Triatlon", "Anders"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Titel (bijv. Marathon onder 3:30)", text: $title)
                    TextField("Extra notities (optioneel)", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(header: Text("Type Sport")) {
                    Picker("Sport", selection: $sportType) {
                        Text("Selecteer een sport").tag("")
                        ForEach(sportTypes, id: \.self) { sport in
                            Text(sport).tag(sport)
                        }
                    }
                }

                Section(header: Text("Streefdatum")) {
                    DatePicker("Datum", selection: $targetDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Nieuw Doel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        saveGoal()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// Sla het nieuwe doel op in SwiftData
    private func saveGoal() {
        let finalSportType = sportType.isEmpty ? nil : sportType
        let finalDetails = details.isEmpty ? nil : details

        let newGoal = FitnessGoal(
            title: title,
            details: finalDetails,
            targetDate: targetDate,
            sportType: finalSportType
        )

        modelContext.insert(newGoal)
        dismiss()
    }
}
