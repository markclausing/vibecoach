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
    // Epic #55: number of consecutive event days (only used for a multi-day stage event).
    @State private var eventDurationDays: Int = 5
    @State private var hasStretchGoal: Bool = false
    // Epic #72 story 72.5: hours:minutes duration instead of a time-of-day DatePicker
    // (a `.hourAndMinute` DatePicker rendered a 3h45 duration as "4:00 AM" on 12-hour locales).
    @State private var stretchHours: Int = 3 // standaard 3:00
    @State private var stretchMinutes: Int = 0

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

                Section(header: Text("Sport & evenement")) {
                    Picker("Sport", selection: $sportCategory) {
                        ForEach(SportCategory.allCases) { category in
                            // Epic #37 story 37.4: displayName stays Dutch for prompts; the UI
                            // picker resolves it via the catalog.
                            Text(LocalizedStringKey(category.displayName)).tag(category)
                        }
                    }

                    Picker("Evenement", selection: $eventFormat) {
                        Text("Eendaagse Race").tag(EventFormat.singleDayRace)
                        Text("Eendaagse Tocht").tag(EventFormat.singleDayTour)
                        Text("Meerdaagse Etappe").tag(EventFormat.multiDayStage)
                    }

                    if eventFormat == .multiDayStage {
                        Stepper("Aantal dagen: \(eventDurationDays)", value: $eventDurationDays, in: 2...21)
                    }

                    Picker("Doel", selection: $primaryIntent) {
                        Text("Uitlopen / Genieten").tag(PrimaryIntent.completion)
                        Text("Presteren / Zo snel mogelijk").tag(PrimaryIntent.peakPerformance)
                    }
                }

                Section(header: Text("Doelstelling"), footer: Text("De coach rekent vanaf deze datum terug om je trainingsfasen te plannen.")) {
                    // Epic #62 story 62.1: forward-bound to the minimum lead time so a new goal
                    // can't be created with a past / too-soon target date.
                    DatePicker(eventFormat == .multiDayStage ? "Startdatum" : "Streefdatum",
                               selection: $targetDate,
                               in: GoalFormValidator.earliestTargetDate()...,
                               displayedComponents: .date)

                    Toggle("Streeftijd instellen", isOn: $hasStretchGoal)

                    if hasStretchGoal {
                        GoalDurationPicker(label: "Finishtijd", hours: $stretchHours, minutes: $stretchMinutes)
                        if let warning = stretchWarning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
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
                    .disabled(!GoalFormValidator.isTitleValid(title)
                              || !GoalFormValidator.isTargetDateValid(targetDate)
                              || isSaving)
                    .accessibilityIdentifier("GoalSaveButton")
                }
            }
        }
    }

    /// Epic #72 story 72.5: hours:minutes duration converted to seconds for storage/validation.
    private var stretchSeconds: TimeInterval {
        TimeInterval(stretchHours * 3600 + stretchMinutes * 60)
    }

    /// Epic #62 story 62.1: inline plausibility hint for the stretch (target finish) time.
    private var stretchWarning: String? {
        guard hasStretchGoal else { return nil }
        switch GoalFormValidator.stretchTimePlausibility(seconds: stretchSeconds, sport: sportCategory) {
        case .ok:      return nil
        case .zero:    return String(localized: "Stel een streeftijd in of zet de schakelaar uit.")
        case .tooFast: return String(localized: "Die streeftijd lijkt erg snel voor deze sport — klopt dat?")
        case .tooSlow: return String(localized: "Die streeftijd lijkt erg lang voor deze sport — klopt dat?")
        }
    }

    /// Save the new goal in SwiftData
    private func saveGoal() {
        isSaving = true
        let finalDetails = details.isEmpty ? nil : details
        let stretchTime: TimeInterval? = hasStretchGoal ? stretchSeconds : nil

        let newGoal = FitnessGoal(
            title: GoalFormValidator.sanitizedTitle(title),
            details: finalDetails,
            targetDate: targetDate,
            sportCategory: sportCategory,
            format: eventFormat,
            intent: primaryIntent,
            stretchGoalTime: stretchTime,
            eventDurationDays: eventFormat == .multiDayStage ? eventDurationDays : nil
        )

        // Determine the Target TRIMP asynchronously via AI or fallback
        Task {
            // Sprint 26.1: skip the Gemini network call in UI-test mode
            // so the goal is saved immediately without network latency.
            // L-6: gate behind #if DEBUG so the bypass cannot exist in a shipped build.
            let isUITesting: Bool = {
                #if DEBUG
                return ProcessInfo.processInfo.arguments.contains("-UITesting")
                #else
                return false
                #endif
            }()
            if isUITesting {
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

    private func fallbackTRIMP(for date: Date) -> Double {
        let days = max(1.0, Calendar.current.fractionalDays(from: Date(), to: date))
        return (days / 7.0) * 350.0
    }
}
