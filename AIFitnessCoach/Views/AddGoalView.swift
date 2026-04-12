import SwiftUI
import SwiftData
import GoogleGenerativeAI

struct AddGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var targetDate = Date().addingTimeInterval(86400 * 30) // +30 dagen
    @State private var sportCategory: SportCategory = .running

    @State private var isSaving = false

    private let profileManager = AthleticProfileManager()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Titel (bijv. Marathon onder 3:30)", text: $title)
                        .accessibilityIdentifier("GoalTitleField")
                    TextField("Extra notities (optioneel)", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(header: Text("Type Sport")) {
                    Picker("Sport", selection: $sportCategory) {
                        ForEach(SportCategory.allCases) { category in
                            Text(category.displayName).tag(category)
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
                    .accessibilityIdentifier("GoalCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveGoal) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Opslaan")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityIdentifier("GoalSaveButton")
                }
            }
        }
    }

    /// Sla het nieuwe doel op in SwiftData
    private func saveGoal() {
        isSaving = true
        let finalDetails = details.isEmpty ? nil : details

        let newGoal = FitnessGoal(
            title: title,
            details: finalDetails,
            targetDate: targetDate,
            sportCategory: sportCategory
        )

        // Bepaal via AI of fallback de Target TRIMP asynchroon
        Task {
            do {
                let currentProfile = try profileManager.calculateProfile(context: modelContext)
                let trimp = await fetchAITargetTRIMP(goal: newGoal, profile: currentProfile)
                newGoal.targetTRIMP = trimp
            } catch {
                // Fallback: ruwe schatting als we geen profiel kunnen inladen
                let days = max(1.0, targetDate.timeIntervalSince(Date()) / 86400)
                newGoal.targetTRIMP = (days / 7.0) * 350.0
            }

            await MainActor.run {
                modelContext.insert(newGoal)
                try? modelContext.save()
                isSaving = false
                dismiss()
            }
        }
    }

    /// Vraag de Gemini AI om een logische TRIMP belasting
    private func fetchAITargetTRIMP(goal: FitnessGoal, profile: AthleticProfile?) async -> Double {
        // Epic 20: BYOK — gebruik de actieve API-sleutel (gebruiker of Secrets-fallback).
        let activeKey = {
            let stored = UserDefaults.standard.string(forKey: "vibecoach_userAPIKey") ?? ""
            return stored.isEmpty ? Secrets.geminiAPIKey : stored
        }()
        guard !activeKey.isEmpty && activeKey != "VUL_HIER_JE_API_KEY_IN" else {
            return fallbackTRIMP(for: goal.targetDate)
        }

        let model = GenerativeModel(
            name: "gemini-2.5-flash",
            apiKey: activeKey
        )

        var profileText = "Geen specifieke historie bekend."
        if let p = profile {
            profileText = "Trainde recent \(p.averageWeeklyVolumeInSeconds / 60) min per week."
        }

        let sport = goal.sportCategory?.displayName ?? "Sport"
        let prompt = """
        De gebruiker heeft als doel '\(goal.title)' (\(sport)) op \(goal.targetDate.formatted(date: .complete, time: .omitted)).
        Het huidige niveau is: \(profileText).
        Vandaag is het \(Date().formatted(date: .complete, time: .omitted)).
        Hoeveel cumulatieve TRIMP is er ruwweg nodig voor deze specifieke voorbereiding vanaf vandaag tot de doeldatum?
        Retourneer UITSLUITEND een logisch, kaal getal (Double of Integer) zonder verdere tekst, leestekens of eenheden. Bijv: 4500.
        """

        do {
            let response = try await model.generateContent(prompt)
            if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), let trimp = Double(text) {
                return trimp
            }
        } catch {
            print("AI TRIMP Fetch failed: \(error)")
        }

        return fallbackTRIMP(for: goal.targetDate)
    }

    private func fallbackTRIMP(for date: Date) -> Double {
        let days = max(1.0, date.timeIntervalSince(Date()) / 86400)
        return (days / 7.0) * 350.0
    }
}
