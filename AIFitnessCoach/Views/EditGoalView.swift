import SwiftUI
import SwiftData

struct EditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var goal: FitnessGoal

    /// Epic #62 story 62.1: invoked right after a successful delete so the host can clear the
    /// goal-derived coach context (no stale prompt references to a removed goal).
    var onDeleted: (() -> Void)?

    // Stretch goal: local state so the DatePicker always gets a valid Date
    @State private var hasStretchGoal: Bool
    @State private var stretchGoalPickerDate: Date

    @State private var showDeleteConfirm = false
    // Guards the onDisappear save: after deleting we must NOT write back to the
    // (now removed) object, otherwise SwiftData would resurrect or crash on it.
    @State private var isDeleting = false

    init(goal: FitnessGoal, onDeleted: (() -> Void)? = nil) {
        self.goal = goal
        self.onDeleted = onDeleted
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
                        // Epic #37 story 37.4: Dutch displayName resolved via catalog for the UI.
                        Text(LocalizedStringKey(category.displayName)).tag(category)
                    }
                }
            }

            Section(header: Text("Type Evenement & Intentie")) {
                Picker("Evenement", selection: Binding<EventFormat>(
                    get: { goal.resolvedFormat },
                    set: { newFormat in
                        goal.format = newFormat
                        // Epic #55: a multi-day stage event must always carry a valid day
                        // count (≥2). Without it `resolvedEventDurationDays` stays 1, so the
                        // goal is NOT recognised as multi-day — no stage entries in the week
                        // schedule and no [EVENT WINDOW] block in the coach prompt.
                        if newFormat == .multiDayStage, (goal.eventDurationDays ?? 0) < 2 {
                            goal.eventDurationDays = 5
                        }
                    }
                )) {
                    Text("Eendaagse Race").tag(EventFormat.singleDayRace)
                    Text("Eendaagse Tocht").tag(EventFormat.singleDayTour)
                    Text("Meerdaagse Etappe").tag(EventFormat.multiDayStage)
                }

                // Epic #55: event duration for a multi-day stage event.
                if goal.resolvedFormat == .multiDayStage {
                    Stepper("Aantal dagen: \(goal.resolvedEventDurationDays)", value: Binding<Int>(
                        get: { goal.resolvedEventDurationDays },
                        set: { goal.eventDurationDays = $0 }
                    ), in: 2...21)
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
                    if let warning = stretchWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section(header: Text("Status")) {
                Toggle("Doel Behaald", isOn: $goal.isCompleted)
                // Epic #55: for a multi-day event `targetDate` is the START day, so label it
                // "Startdatum" (matching AddGoalView). For single-day goals it stays the target date.
                // Epic #62 story 62.1: forward-bound the picker so a goal can't be edited to a
                // date inside the minimum lead time; an already-too-soon legacy date is flagged below.
                DatePicker(goal.resolvedFormat == .multiDayStage ? "Startdatum" : "Streefdatum",
                           selection: $goal.targetDate,
                           in: GoalFormValidator.earliestTargetDate()...,
                           displayedComponents: .date)
                if !GoalFormValidator.isTargetDateValid(goal.targetDate) {
                    Label("Datum ligt te dichtbij — kies minstens \(GoalFormValidator.minimumLeadDays) dagen vooruit.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Verwijder doel", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Bewerk Doel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Epic #55: backfill the day count for an existing multi-day goal that lacks one
            // (e.g. created before Epic #55, or format switched without touching the stepper).
            // Otherwise it is silently not treated as multi-day (no stage entries / event window).
            if goal.resolvedFormat == .multiDayStage, (goal.eventDurationDays ?? 0) < 2 {
                goal.eventDurationDays = 5
            }
        }
        .confirmationDialog(
            "Dit doel verwijderen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) {
                isDeleting = true
                modelContext.delete(goal)
                try? modelContext.save()
                // Epic #62 story 62.1: let the host forget this goal's coach context immediately.
                onDeleted?()
                dismiss()
            }
            Button("Annuleren", role: .cancel) { }
        } message: {
            Text("Dit verwijdert het doel en het bijbehorende schema definitief.")
        }
        .onDisappear {
            // Don't write back to a deleted goal.
            guard !isDeleting else { return }
            // Epic #62 story 62.1: trim the title so trailing whitespace/newlines aren't persisted.
            goal.title = GoalFormValidator.sanitizedTitle(goal.title)
            goal.stretchGoalTime = hasStretchGoal ? stretchTimeInterval(from: stretchGoalPickerDate) : nil
            try? modelContext.save()
        }
    }

    /// Epic #62 story 62.1: inline plausibility hint for the stretch (target finish) time.
    private var stretchWarning: String? {
        guard hasStretchGoal else { return nil }
        let seconds = stretchTimeInterval(from: stretchGoalPickerDate)
        switch GoalFormValidator.stretchTimePlausibility(seconds: seconds, sport: goal.sportCategory ?? .other) {
        case .ok:      return nil
        case .zero:    return String(localized: "Stel een streeftijd in of zet de schakelaar uit.")
        case .tooFast: return String(localized: "Die streeftijd lijkt erg snel voor deze sport — klopt dat?")
        case .tooSlow: return String(localized: "Die streeftijd lijkt erg lang voor deze sport — klopt dat?")
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
