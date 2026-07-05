import SwiftUI
import PhotosUI
import SwiftData

// swiftlint:disable file_length
// Epic 65.6 size backstop: ChatView was split 1444→677 in 65.5; the residual is
// the core chat surface + its tightly-coupled input bar. Just over the 600 cap.

/// The main SwiftUI view that displays the chat interface.
struct ChatView: View {
    /// The viewmodel that manages the chat state and network logic.
    @ObservedObject var viewModel: ChatViewModel

    /// Current item selected from the iOS Photos library.
    @State private var selectedItem: PhotosPickerItem?

    /// The global app state to intercept notification-tap actions.
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var themeManager: ThemeManager

    /// SwiftData Context for computing the athletic profile.
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @State private var currentProfile: AthleticProfile?

    /// Active user preferences from SwiftData
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

    /// Epic 34 Sprint 2: recent activities and readiness for the data-driven coach cards.
    @Query(sort: \ActivityRecord.startDate, order: .reverse) private var recentActivities: [ActivityRecord]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var recentReadiness: [DailyReadiness]

    /// Epic #70: facts distilled in per-workout chats — feed the [WORKOUT NOTES]
    /// prompt block. The 14-day window/cap policy lives in the formatter; this
    /// query stays unfiltered because the fact volume is inherently small.
    @Query(sort: \WorkoutChatFact.createdAt, order: .reverse) private var workoutChatFacts: [WorkoutChatFact]

    /// Tracks whether the user has dismissed the overtraining warning banner.
    @State private var warningDismissed = false

    private let profileManager = AthleticProfileManager()

    /// Epic #70: the invocation context for every coach call from this view.
    /// One computed helper (instead of 7 inline constructions) so the
    /// workout-notes block is threaded consistently everywhere.
    private var coachInvocation: CoachInvocationContext {
        CoachInvocationContext(profile: currentProfile,
                               activeGoals: goals,
                               activePreferences: activePreferences,
                               workoutNotesBlock: workoutNotesBlock)
    }

    /// Builds the [WORKOUT NOTES] block: flattens the facts to formatter items with
    /// the source workout's display name looked up in the already-queried activities.
    private var workoutNotesBlock: String {
        guard !workoutChatFacts.isEmpty else { return "" }
        let labelByID = Dictionary(uniqueKeysWithValues: recentActivities.map { ($0.id, $0.displayName) })
        let items = workoutChatFacts.map { fact in
            WorkoutFactsContextFormatter.Item(text: fact.factText,
                                              category: fact.category,
                                              createdAt: fact.createdAt,
                                              workoutLabel: labelByID[fact.activityID] ?? "")
        }
        return WorkoutFactsContextFormatter.format(items: items)
    }

    // Epic 34.1: V2.0 Fit & Finish — scroll state for the material overlay in the top safe area.
    @State private var isChatScrolled: Bool = false

    // Epic #51-A2: AppStorage snapshot of the model choice. We need the values
    // here (instead of only in ChatViewModel) so SwiftUI re-renders the
    // `modelSwitchNotice` banner as soon as the user switches in Settings —
    // a computed property on the viewmodel alone does not trigger a
    // view update.
    @AppStorage(AIModelAppStorageKey.primary) private var configuredPrimaryModel: String = AIModelAppStorageKey.defaultPrimary
    @AppStorage(AIModelAppStorageKey.fallback) private var configuredFallbackModel: String = AIModelAppStorageKey.defaultFallback

    // Epic #51-A3: whether the user has expanded the archive of older messages.
    // Default `false` keeps long conversations short on screen;
    // tapping the "Toon eerdere X berichten" row toggles the whole archive.
    @State private var showArchivedMessages: Bool = false

    // Epic #51-A4: short toast text when a paste exceeded the char limit
    // and was trimmed automatically. `nil` when there is nothing to report.
    @State private var inputTrimNotice: String?

    /// Updates the current profile from SwiftData.
    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            AppLoggers.userProfile.error("Profile load failed in ChatView: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Data-driven KORT + WAT IK ZIE (Epic 34 Sprint 2)
    //
    // These derivations combine the last stored coach insight with the most
    // recent SwiftData records (ActivityRecord, DailyReadiness, AthleticProfile)
    // so the UI never shows made-up numbers.

    /// Short coach summary — falls back to the last insight stored by the LLM.
    private var coachSummaryText: String? {
        let stored = viewModel.latestStoredInsight.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? nil : stored
    }

    /// Active injury zones derived from active UserPreferences (InjuryMemory).
    private var activeInjuries: [BodyArea] {
        BodyArea.allCases.filter { area in
            activePreferences.contains { pref in
                area.matchesInjuryKeyword(in: pref.preferenceText)
            }
        }
    }

    /// Observations derived from the most recent SwiftData records.
    /// Empty → we show a motivating fallback so the card is never bare.
    private var coachInsightLines: [String] {
        var lines: [String] = []

        // Vibe Score → battery tier
        if let readiness = recentReadiness.first {
            let hrv = Int(readiness.hrv.rounded())
            if readiness.readinessScore < 50 {
                lines.append("Lage batterij (Vibe \(readiness.readinessScore)/100) — prioriteit is vandaag herstel.")
            } else if readiness.readinessScore >= 80 {
                lines.append("Volle batterij (Vibe \(readiness.readinessScore)/100) — goede dag voor intensiteit.")
            } else {
                lines.append("Vibe \(readiness.readinessScore)/100 · HRV \(hrv) ms — houd het gematigd.")
            }
        }

        // Active injuries from InjuryMemory
        let injuries = activeInjuries
        if !injuries.isEmpty {
            let names = injuries.map { $0.rawValue.lowercased() }.joined(separator: ", ")
            lines.append("Blessuregeheugen actief: \(names). Plan ontziet deze zone.")
        }

        if let lastActivity = recentActivities.first {
            let km = String(format: "%.1f", lastActivity.distance / 1000).replacingOccurrences(of: ".", with: ",")
            let trimpText = lastActivity.trimp.map { " · TRIMP \(Int($0.rounded()))" } ?? ""
            lines.append("Laatste training: \(lastActivity.displayName) · \(km) km\(trimpText).")
        }

        if let profile = currentProfile, profile.isRecoveryNeeded {
            let reason = profile.recoveryReason ?? "Trainingsbelasting boven baseline."
            lines.append("Herstelsignaal: \(reason)")
        }

        // Motivating fallback when there is no data yet
        if lines.isEmpty {
            lines.append("Luister naar je lichaam. Elke stap telt — ook de rustdagen.")
        }

        return lines
    }

private let suggestionChips = [
        "Wat moet ik morgen doen?",
        "Hoe is mijn herstel?",
        "Pas mijn plan aan",
        "Verklaar mijn HRV"
    ]

    // MARK: - Phase label from goals

    private var coachPhaseLabel: String {
        let goal = goals.first(where: { !$0.isCompleted })
        // Epic #37 story 37.1c: rendered via Text(phaseLabel) -> verbatim, so resolve via catalog.
        guard let phase = goal?.currentPhase else { return String(localized: "Kent je plan") }
        let cal = Calendar.current
        let weeksRemaining = goal.flatMap { g -> Double? in
            guard g.targetDate > Date() else { return nil }
            return Double(cal.dateComponents([.weekOfYear], from: Date(), to: g.targetDate).weekOfYear ?? 0)
        } ?? 0
        let weekInPhase: Int
        switch phase {
        case .buildPhase:  weekInPhase = max(1, Int(12 - weeksRemaining) + 1)
        case .peakPhase:   weekInPhase = max(1, Int(4  - weeksRemaining) + 1)
        case .tapering:    weekInPhase = max(1, Int(2  - weeksRemaining) + 1)
        default:           weekInPhase = 1
        }
        let totalWeeks: Int
        switch phase {
        case .buildPhase:  totalWeeks = 8
        case .peakPhase:   totalWeeks = 2
        case .tapering:    totalWeeks = 2
        default:
            let created = goal?.createdAt ?? Date()
            let target  = goal?.targetDate ?? Date()
            totalWeeks  = max(1, (cal.dateComponents([.weekOfYear], from: created, to: target).weekOfYear ?? 12) - 12)
        }
        return String(localized: "Kent je plan • \(phase.displayName) • wk \(weekInPhase)/\(totalWeeks)")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── V2 Custom header
                CoachV2HeaderView(
                    phaseLabel: coachPhaseLabel,
                    accentColor: themeManager.primaryAccentColor
                )
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 12)
                .background(Color(.secondarySystemBackground))

                // Under XCUITest the Keychain write from `UITestMockEnvironment.setup()`
                // is not always reliably honoured on the GitHub runner — bypass the
                // gate then so the Coach UI renders and the mock LLM (`UITestMockGenerativeModel`)
                // does the work. Production remains fully dependent on `hasAPIKey`.
                // L-6: the bypass exists only in DEBUG builds, so the path cannot
                // be present in a shipped binary (matches makeModelContainer's pattern).
                let isUITesting: Bool = {
                    #if DEBUG
                    return ProcessInfo.processInfo.arguments.contains("-UITesting")
                    #else
                    return false
                    #endif
                }()
                if !viewModel.hasAPIKey && !isUITesting {
                    NoAPIKeyView()
                } else {

                    // Epic #51-A2: model-switch banner — only appears during
                    // isTyping when the user switches Gemini model in Settings.
                    // Text lives in `ChatModelSwitchNotice` (pure-Swift, separately testable).
                    if let switchNotice = ChatModelSwitchNotice.message(
                        activePrimary: viewModel.activeRequestPrimaryModel,
                        activeFallback: viewModel.activeRequestFallbackModel,
                        configuredPrimary: configuredPrimaryModel,
                        configuredFallback: configuredFallbackModel
                    ), viewModel.isTyping {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                            Text(switchNotice)
                                .font(.caption).fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .overlay(Color.blue.opacity(0.10))
                        .foregroundStyle(.primary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("ChatModelSwitchBanner")
                    }

                    // Warning banner (retained)
                    if currentProfile?.isRecoveryNeeded == true && !warningDismissed {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                            Text("Trainingsvolume te hoog — neem rust.")
                                .font(.caption).fontWeight(.medium)
                            Spacer()
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { warningDismissed = true }
                            } label: {
                                Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .overlay(Color.orange.opacity(0.10))
                        .foregroundStyle(.primary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ── Scroll area
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {

                                // ── Epic 34 Sprint 2: data-driven KORT + WAT IK ZIE
                                // The cards only show real SwiftData/coach output.
                                // If both are empty → no placeholder noise.
                                if let summary = coachSummaryText {
                                    CoachTextCard(
                                        text: summary,
                                        accentColor: themeManager.primaryAccentColor
                                    )
                                }

                                if !coachInsightLines.isEmpty {
                                    CoachInsightCard(
                                        insights: coachInsightLines,
                                        accentColor: themeManager.primaryAccentColor
                                    )
                                }

                                // ── Existing chat messages (below the separator line)
                                if !viewModel.messages.isEmpty {
                                    HStack {
                                        Rectangle()
                                            .fill(Color(.separator))
                                            .frame(height: 1)
                                        Text("CHATGESCHIEDENIS")
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundColor(.secondary).kerning(0.5)
                                            .fixedSize()
                                        Rectangle()
                                            .fill(Color(.separator))
                                            .frame(height: 1)
                                    }
                                    .padding(.vertical, 8)

                                    // Epic #51-A3: split long conversations into a collapsed archive
                                    // (oldest messages) + a visible tail. ConversationTrimmer
                                    // is a pure-Swift split helper without ChatMessage deps.
                                    let trim = ChatConversationTrimmer.split(messages: viewModel.messages)

                                    if !trim.archived.isEmpty {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                showArchivedMessages.toggle()
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: showArchivedMessages ? "chevron.down" : "chevron.right")
                                                    .font(.caption2)
                                                Text(showArchivedMessages
                                                     ? "Verberg \(trim.archived.count) eerdere berichten"
                                                     : "Toon \(trim.archived.count) eerdere berichten")
                                                    .font(.caption).fontWeight(.medium)
                                                Spacer()
                                            }
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8).padding(.vertical, 6)
                                            .background(Color(.tertiarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        .accessibilityIdentifier("ChatArchiveToggle")

                                        if showArchivedMessages {
                                            ForEach(trim.archived) { message in
                                                MessageBubble(
                                                    message: message,
                                                    onSkipWorkout: { workout in
                                                        refreshProfileContext()
                                                        viewModel.skipWorkout(workout, invocation: coachInvocation)
                                                    },
                                                    onAlternativeWorkout: { workout in
                                                        refreshProfileContext()
                                                        viewModel.requestAlternativeWorkout(workout, invocation: coachInvocation)
                                                    },
                                                    onRetry: {
                                                        refreshProfileContext()
                                                        viewModel.retryLastMessage(invocation: coachInvocation)
                                                    }
                                                )
                                                .id(message.id)
                                                .opacity(0.85)
                                            }
                                        }
                                    }

                                    ForEach(trim.visible) { message in
                                        MessageBubble(
                                            message: message,
                                            onSkipWorkout: { workout in
                                                refreshProfileContext()
                                                viewModel.skipWorkout(workout, invocation: coachInvocation)
                                            },
                                            onAlternativeWorkout: { workout in
                                                refreshProfileContext()
                                                viewModel.requestAlternativeWorkout(workout, invocation: coachInvocation)
                                            },
                                            onRetry: {
                                                refreshProfileContext()
                                                viewModel.retryLastMessage(invocation: coachInvocation)
                                            }
                                        )
                                        .id(message.id)
                                    }
                                }

                                // Loading indicator
                                if viewModel.isTyping {
                                    HStack {
                                        ProgressView().padding(.trailing, 8)
                                        Text(viewModel.retryStatusMessage.isEmpty
                                             ? "Coach is aan het typen..."
                                             : viewModel.retryStatusMessage)
                                            .font(.caption)
                                            .foregroundColor(viewModel.retryStatusMessage.isEmpty ? .gray : .orange)
                                        Spacer()
                                    }
                                    .padding()
                                    .id("typingIndicator")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y > 4
                        } action: { _, newValue in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isChatScrolled = newValue
                            }
                        }
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .onChange(of: viewModel.messages) { _, _ in
                            if let last = viewModel.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onChange(of: viewModel.isTyping) { _, isTyping in
                            if isTyping { withAnimation { proxy.scrollTo("typingIndicator", anchor: .bottom) } }
                        }
                    }

                    // Image preview
                    if let image = viewModel.selectedImage {
                        HStack {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button { viewModel.clearImage(); selectedItem = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.horizontal).padding(.top, 8)
                    }

                    // ── OF VRAAG chips
                    SuggestionChipsView(suggestions: suggestionChips) { suggestion in
                        viewModel.inputText = suggestion
                    }

                    Divider()

                    // Epic #51-A4: char counter + trim toast. The counter only
                    // appears from 80% of the limit so the UI stays calm during
                    // normal typing; the toast is set by the clamp `onChange`
                    // below as soon as a paste was trimmed.
                    if ChatInputValidator.shouldShowCounter(viewModel.inputText) {
                        HStack {
                            Spacer()
                            Text("\(viewModel.inputText.count) / \(ChatInputValidator.maxLength)")
                                .font(.caption2)
                                .foregroundStyle(viewModel.inputText.count >= ChatInputValidator.maxLength ? .orange : .secondary)
                        }
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("ChatInputCounter")
                    }
                    if let trimNotice = inputTrimNotice {
                        HStack(spacing: 6) {
                            Image(systemName: "scissors").font(.caption2)
                            Text(trimNotice).font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("ChatInputTrimNotice")
                    }

                    // ── Input bar
                    HStack(alignment: .bottom, spacing: 12) {
                        // Epic 39 Story 39.2: PhotosPicker's label closure is @Sendable;
                        // referencing main-actor properties directly triggers a warning.
                        // Read the color into a local `let` so the closure captures it.
                        let accentColor = themeManager.primaryAccentColor
                        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "plus")
                                .font(.system(size: 20))
                                .foregroundStyle(accentColor)
                                .padding(8)
                                .background(accentColor.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    viewModel.selectedImage = uiImage
                                }
                            }
                        }

                        TextField("Bericht...", text: $viewModel.inputText, axis: .vertical)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                            .lineLimit(1...5)
                            .accessibilityIdentifier("ChatInputField")
                            // Epic #51-A4: clamp inputText to `maxLength`. A
                            // paste that exceeds the limit gets trimmed and
                            // the toast appears once. We only write back
                            // when the value actually changes
                            // to avoid a feedback loop.
                            .onChange(of: viewModel.inputText) { _, newValue in
                                let result = ChatInputValidator.clamp(newValue)
                                if result.didClamp {
                                    viewModel.inputText = result.clamped
                                    inputTrimNotice = String(localized: "Tekst ingekort tot \(ChatInputValidator.maxLength) tekens.")
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        inputTrimNotice = nil
                                    }
                                }
                            }

                        Button(action: {
                            refreshProfileContext()
                            Haptics.impact(.medium)
                            viewModel.sendMessage(invocation: coachInvocation)
                            selectedItem = nil
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(viewModel.inputText.isEmpty && viewModel.selectedImage == nil ? Color.secondary : themeManager.primaryAccentColor)
                        }
                        .disabled(viewModel.inputText.isEmpty && viewModel.selectedImage == nil)
                        .accessibilityIdentifier("ChatSendButton")
                    }
                    .padding()

                } // end else (hasAPIKey)
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeMaterial(isActive: isChatScrolled)
            .onAppear {
                refreshProfileContext()
                setupPreferenceCallback()
                showWelcomeInsightIfNeeded()
            }
            // Epic #51-A6: on tab switch or view dismiss we cancel an
            // ongoing AI call so no "ghost" response appears on return
            // and the spinner does not keep spinning forever.
            .onDisappear {
                viewModel.cancelOngoingRequest()
            }
        }
    }

    /// SPRINT 13.4: Shows the stored coach insight as a welcome message when the chat is empty.
    /// This way the user sees the coach's explanation right after navigating to the Coach tab,
    /// even if the AI already finished before they opened the tab.
    private func showWelcomeInsightIfNeeded() {
        guard viewModel.messages.isEmpty else { return }
        let insight = viewModel.latestStoredInsight
        guard !insight.isEmpty else { return }
        viewModel.injectWelcomeMessage(insight)
    }

    /// Sets up the callback in the ViewModel to store detected preferences in SwiftData
    private func setupPreferenceCallback() {
        viewModel.onNewPreferencesDetected = { detectedPrefs in
            let context = modelContext
            Task { @MainActor in
                // Because activePreferences is already fetched via @Query, we can use it for a check.
                let existingTexts = activePreferences.map { $0.preferenceText.lowercased() }

                let dateFormatter = AppDateFormatters.fixed("yyyy-MM-dd")

                var hasNew = false
                for pref in detectedPrefs {
                    let lowerText = pref.text.lowercased()

                    // Only add if the same (exact or near-exact) text is not already in the list
                    if !existingTexts.contains(where: { existing in
                        existing.contains(lowerText) || lowerText.contains(existing)
                    }) {
                        var parsedDate: Date?
                        if let dateString = pref.expirationDate, !dateString.isEmpty {
                            parsedDate = dateFormatter.date(from: dateString)
                        }

                        let newPref = UserPreference(preferenceText: pref.text, expirationDate: parsedDate)
                        context.insert(newPref)
                        hasNew = true
                    }
                }

                if hasNew {
                    try? context.save()
                }
            }
        }
    }
}

/// Epic 20: Empty state shown when no API key is configured.
/// Sends the user directly to the AI Coach Configuration in Settings.
struct NoAPIKeyView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Je AI Coach slaapt")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Voer een API-sleutel in via de Instellingen om hem wakker te maken.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            NavigationLink(destination: AIProviderSettingsView()) {
                Label("Naar Instellingen", systemImage: "gear")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.primaryAccentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            Spacer()
        }
    }
}

/// A reusable view component that draws a single chat message.
struct MessageBubble: View {
    /// The message to display.
    let message: ChatMessage
    @EnvironmentObject var themeManager: ThemeManager

    // Callbacks for the workout cards
    var onSkipWorkout: ((SuggestedWorkout) -> Void)?
    var onAlternativeWorkout: ((SuggestedWorkout) -> Void)?

    /// Callback for the 'Probeer opnieuw' button on error messages.
    var onRetry: (() -> Void)?

    /// Determines whether the sender is the user (right-aligned and blue).
    var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if let imageData = message.attachedImageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(8)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isUser
                                    ? AnyShapeStyle(themeManager.primaryAccentColor)
                                    : (message.isError
                                        ? AnyShapeStyle(Color.orange.opacity(0.12))
                                        : AnyShapeStyle(Material.ultraThin)))
                        }
                        .foregroundStyle(isUser
                            ? Color.white.opacity(0.92)
                            : (message.isError ? Color.orange : Color.primary))
                }

                // Retry button — only visible on recoverable error messages
                if message.isError, let onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text("Probeer opnieuw")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                    }
                }
            }

            if !isUser { Spacer() }
        }
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel())
        .environmentObject(AppNavigationState())
}
