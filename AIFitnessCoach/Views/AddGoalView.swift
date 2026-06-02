import SwiftUI
import SwiftData

struct AddGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var sportCategory: SportCategory = .running

    // Epic Doel-Intenties
    @State private var eventFormat: EventFormat = .singleDayRace
    @State private var primaryIntent: PrimaryIntent = .peakPerformance
    @State private var hasStretchGoal: Bool = false
    @State private var stretchGoalPickerDate: Date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3 * 3600) // standaard 3:00

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

                Section(header: Text("Type Evenement & Intentie")) {
                    Picker("Evenement", selection: $eventFormat) {
                        Text("Eendaagse Race").tag(EventFormat.singleDayRace)
                        Text("Eendaagse Tocht").tag(EventFormat.singleDayTour)
                        Text("Meerdaagse Etappe").tag(EventFormat.multiDayStage)
                    }

                    Picker("Doel", selection: $primaryIntent) {
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

    /// Save the new goal in SwiftData
    private func saveGoal() {
        isSaving = true
        let finalDetails = details.isEmpty ? nil : details
        let stretchTime: TimeInterval? = hasStretchGoal ? stretchTimeInterval(from: stretchGoalPickerDate) : nil

        let newGoal = FitnessGoal(
            title: title,
            details: finalDetails,
            targetDate: targetDate,
            sportCategory: sportCategory,
            format: eventFormat,
            intent: primaryIntent,
            stretchGoalTime: stretchTime
        )

        // Determine the Target TRIMP asynchronously via AI or fallback
        Task {
            // Sprint 26.1: skip the Gemini network call in UI-test mode
            // so the goal is saved immediately without network latency.
            if ProcessInfo.processInfo.arguments.contains("-UITesting") {
                newGoal.targetTRIMP = fallbackTRIMP(for: targetDate)
            } else {
                do {
                    let currentProfile = try profileManager.calculateProfile(context: modelContext)
                    let trimp = await fetchAITargetTRIMP(goal: newGoal, profile: currentProfile)
                    newGoal.targetTRIMP = trimp
                } catch {
                    // Fallback: rough estimate if we can't load a profile
                    let days = max(1.0, Calendar.current.fractionalDays(from: Date(), to: targetDate))
                    newGoal.targetTRIMP = (days / 7.0) * 350.0
                }
            }

            await MainActor.run {
                modelContext.insert(newGoal)
                try? modelContext.save()
                isSaving = false
                Haptics.impact(.medium)
                dismiss()
            }
        }
    }

    /// Ask the Gemini AI for a logical TRIMP load
    private func fetchAITargetTRIMP(goal: FitnessGoal, profile: AthleticProfile?) async -> Double {
        // Epic 20 / M-04: BYOK — only the key configured by the user.
        // C-02: the key comes from the Keychain instead of UserDefaults. Epic #53: per-provider.
        let provider = AIProvider.current()
        let activeKey = UserAPIKeyStore.read(for: provider)
        guard !activeKey.isEmpty else {
            return fallbackTRIMP(for: goal.targetDate)
        }

        var profileText = "No specific history known."
        if let p = profile {
            profileText = "Recently trained \(p.averageWeeklyVolumeInSeconds / 60) min per week."
        }

        let sport = goal.sportCategory?.displayName ?? "Sport"
        let prompt = """
        The user's goal is '\(goal.title)' (\(sport)) on \(goal.targetDate.formatted(date: .complete, time: .omitted)).
        The current level is: \(profileText).
        Today is \(Date().formatted(date: .complete, time: .omitted)).
        Roughly how much cumulative TRIMP is needed for this specific preparation from today until the target date?
        Return ONLY a logical, bare number (Double or Integer) without any further text, punctuation or units. E.g.: 4500.
        """

        // Epic #53: provider-agnostic via the `AIModelFactory`. No system
        // instruction and no JSON mode — we ask for a single bare number back. The
        // model name follows the user's model choice for this provider.
        func requestTRIMP(modelName: String) async throws -> Double? {
            let model = AIModelFactory.makeModel(
                provider: provider,
                modelName: modelName,
                systemInstruction: "",
                jsonMode: false,
                timeout: 30,
                apiKey: activeKey
            )
            let response = try await model.generateContent([.text(prompt)])
            if let text = response?.trimmingCharacters(in: .whitespacesAndNewlines), let trimp = Double(text) {
                return trimp
            }
            return nil
        }

        do {
            if let trimp = try await requestTRIMP(modelName: AIModelAppStorageKey.resolvedPrimary(for: provider)) {
                return trimp
            }
        } catch {
            // On temporary overload (503/429) silently retry with the lighter fallback model.
            if AIProviderError.isOverload(error),
               let trimp = try? await requestTRIMP(modelName: AIModelAppStorageKey.resolvedFallback(for: provider)) {
                return trimp
            }
        }

        return fallbackTRIMP(for: goal.targetDate)
    }

    /// Converts the hour:minute value of a Date to a TimeInterval (seconds).
    private func stretchTimeInterval(from date: Date) -> TimeInterval {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return TimeInterval(h * 3600 + m * 60)
    }

    private func fallbackTRIMP(for date: Date) -> Double {
        let days = max(1.0, Calendar.current.fractionalDays(from: Date(), to: date))
        return (days / 7.0) * 350.0
    }
}
