import SwiftUI
import SwiftData

// MARK: - Epic #70 story 70.4: inline "Discuss this workout" chat

/// The per-workout chat section at the bottom of `WorkoutAnalysisView`.
///
/// Owns the SwiftData side of the feature: it queries the persisted thread
/// (`WorkoutChatEntry`) and the distilled facts (`WorkoutChatFact`) for this
/// activity, and wires the SwiftData-free `WorkoutChatViewModel` to persistence
/// via its callbacks (the `onNewPreferencesDetected` split, see the view model's
/// doc comment). The fact chips carry the single management surface: ✕ hard-deletes
/// a fact (maintainer decision — no Settings surface).
struct WorkoutChatSection: View {

    let activity: ActivityRecord

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager

    @Query private var entries: [WorkoutChatEntry]
    @Query private var facts: [WorkoutChatFact]

    @StateObject private var viewModel: WorkoutChatViewModel

    @State private var draft: String = ""
    @State private var showFullThread = false

    /// Messages shown when the thread is collapsed. Older ones sit behind the expander.
    private static let collapsedMessageLimit = 6

    init(activity: ActivityRecord) {
        self.activity = activity
        let activityID = activity.id
        _entries = Query(
            filter: #Predicate<WorkoutChatEntry> { $0.activityID == activityID },
            sort: \WorkoutChatEntry.timestamp,
            order: .forward
        )
        _facts = Query(
            filter: #Predicate<WorkoutChatFact> { $0.activityID == activityID },
            sort: \WorkoutChatFact.createdAt,
            order: .forward
        )
        _viewModel = StateObject(wrappedValue: WorkoutChatViewModel(workout: .init(
            activityID: activity.id,
            name: activity.displayName,
            date: activity.startDate,
            sportRaw: activity.sportCategory.rawValue,
            sessionTypeLabel: activity.sessionType?.displayName,
            trimp: activity.trimp,
            movingTimeMinutes: activity.movingTime / 60,
            averageHeartrate: activity.averageHeartrate,
            rpe: activity.rpe,
            mood: activity.mood
        )))
    }

    // Sprint 26.1 pattern (see ChatView): during `-UITesting` the mock model answers,
    // so the key gate must not hide the input. DEBUG-only bypass per CLAUDE.md §6.
    private var hasAPIKey: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") { return true }
        #endif
        return viewModel.hasAPIKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bespreek deze workout", systemImage: "bubble.left.and.text.bubble.right")
                .font(.headline)

            if !facts.isEmpty {
                factChipsRow
            }

            if !viewModel.messages.isEmpty {
                threadView
            }

            if viewModel.isTyping {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("De coach denkt na…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if hasAPIKey {
                inputBar
            } else {
                Text("Stel eerst een API-sleutel in via Instellingen om over deze workout te chatten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear(perform: wireUpViewModel)
        .accessibilityIdentifier("workoutChatSection")
    }

    // MARK: - Fact chips (the single fact-management surface)

    private var factChipsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Onthouden over deze workout")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(facts) { fact in
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption2)
                            Text(fact.factText)
                                .font(.caption)
                                .lineLimit(2)
                            Button {
                                modelContext.delete(fact)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(Text("Verwijder onthouden feit"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(themeManager.primaryAccentColor.opacity(0.12),
                                    in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Thread

    private var visibleMessages: [ChatMessage] {
        guard !showFullThread, viewModel.messages.count > Self.collapsedMessageLimit else {
            return viewModel.messages
        }
        return Array(viewModel.messages.suffix(Self.collapsedMessageLimit))
    }

    private var threadView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !showFullThread, viewModel.messages.count > Self.collapsedMessageLimit {
                Button {
                    withAnimation { showFullThread = true }
                } label: {
                    Text("Toon alle berichten (\(String(viewModel.messages.count)))")
                        .font(.caption)
                }
            }
            ForEach(visibleMessages) { message in
                MessageBubble(message: message)
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Vraag of vertel iets over deze workout…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("workoutChatInput")
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend
                            ? AnyShapeStyle(themeManager.primaryAccentColor)
                            : AnyShapeStyle(Color.secondary))
                }
                .disabled(!canSend)
                .accessibilityIdentifier("workoutChatSend")
            }
            if ChatInputValidator.shouldShowCounter(draft) {
                Text(verbatim: "\(draft.count)/\(ChatInputValidator.maxLength)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isTyping
    }

    private func send() {
        let text = draft
        draft = ""
        viewModel.sendMessage(text, existingFactTexts: facts.map(\.factText))
    }

    // MARK: - Persistence wiring (the SwiftData side of the callback split)

    private func wireUpViewModel() {
        viewModel.loadHistory(entries.map { (role: $0.role, text: $0.text, timestamp: $0.timestamp) })

        let activityID = activity.id
        viewModel.onMessagePersisted = { role, text, date in
            modelContext.insert(WorkoutChatEntry(activityID: activityID,
                                                 role: role,
                                                 text: text,
                                                 timestamp: date))
            try? modelContext.save()
        }
        viewModel.onNewFactsDetected = { newFacts in
            // Containment-dedupe against the *current* store state (fetched fresh —
            // the @Query snapshot may be stale inside this escaping closure), the
            // ChatView newPreferences pattern.
            let descriptor = FetchDescriptor<WorkoutChatFact>(
                predicate: #Predicate { $0.activityID == activityID }
            )
            let existing = ((try? modelContext.fetch(descriptor)) ?? []).map { $0.factText.lowercased() }
            var inserted = false
            for fact in newFacts {
                let lower = fact.text.lowercased()
                let isDuplicate = existing.contains { $0.contains(lower) || lower.contains($0) }
                guard !isDuplicate else { continue }
                modelContext.insert(WorkoutChatFact(activityID: activityID,
                                                    factText: fact.text,
                                                    category: fact.category))
                inserted = true
            }
            if inserted { try? modelContext.save() }
        }
    }
}
