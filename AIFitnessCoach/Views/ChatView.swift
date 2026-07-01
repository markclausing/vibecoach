import SwiftUI
import PhotosUI
import SwiftData

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

    /// Tracks whether the user has dismissed the overtraining warning banner.
    @State private var warningDismissed = false

    private let profileManager = AthleticProfileManager()

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
                let text = pref.preferenceText.lowercased()
                return area.injuryKeywords.contains(where: { text.contains($0) })
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
                                                        viewModel.skipWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                                    },
                                                    onAlternativeWorkout: { workout in
                                                        refreshProfileContext()
                                                        viewModel.requestAlternativeWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                                    },
                                                    onRetry: {
                                                        refreshProfileContext()
                                                        viewModel.retryLastMessage(contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
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
                                                viewModel.skipWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                            },
                                            onAlternativeWorkout: { workout in
                                                refreshProfileContext()
                                                viewModel.requestAlternativeWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                            },
                                            onRetry: {
                                                refreshProfileContext()
                                                viewModel.retryLastMessage(contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
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
                            viewModel.sendMessage(contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
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

// MARK: - Coach Card Components

// MARK: CoachV2HeaderView

struct CoachV2HeaderView: View {
    let phaseLabel: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(accentColor)
                Circle()
                    .fill(Color.green)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Coach")
                    .font(.title2).fontWeight(.bold)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(phaseLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CoachView")
    }
}

// MARK: CoachTextCard

struct CoachTextCard: View {
    let text: String
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            coachAvatar(accentColor)
            VStack(alignment: .leading, spacing: 8) {
                Text("KORT")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(accentColor).kerning(0.8)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: CoachInsightCard

struct CoachInsightCard: View {
    let insights: [String]
    let accentColor: Color

    @State private var isExpanded = false

    private var visibleCount: Int { isExpanded ? insights.count : min(1, insights.count) }
    private var hiddenCount: Int { max(0, insights.count - 1) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            coachAvatar(accentColor)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption).foregroundColor(accentColor)
                    Text("WAT IK ZIE")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.secondary).kerning(0.8)
                }
                ForEach(Array(insights.prefix(visibleCount).enumerated()), id: \.offset) { _, insight in
                    Text(insight)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hiddenCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Minder tonen" : "Meer uitleg (\(hiddenCount))")
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: PlanAdjustmentCard

struct PlanAdjustment: Identifiable {
    let id = UUID()
    let dayAbbr: String
    let dayNum: Int
    let original: String
    let replacement: String
}

struct PlanAdjustmentCard: View {
    let adjustments: [PlanAdjustment]
    let accentColor: Color
    var onApply: () -> Void
    var onView: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundColor(accentColor)
                    Text("AANPASSING IN JE PLAN")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.secondary).kerning(0.5)
                }
                Spacer()
                Text("Voorstel")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            // Adjustment rows
            VStack(spacing: 14) {
                ForEach(adjustments) { adj in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Text(adj.dayAbbr)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("\(adj.dayNum)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(adj.original)
                                .font(.subheadline)
                                .strikethrough(true, color: .secondary)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(accentColor)
                                Text(adj.replacement)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            Divider().padding(.horizontal, 14)

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onApply) {
                    Text("Toepassen")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(action: onView) {
                    HStack(spacing: 4) {
                        Text("Bekijk")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .padding(.vertical, 14).padding(.horizontal, 20)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
                }
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: SuggestionChipsView

struct SuggestionChipsView: View {
    let suggestions: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OF VRAAG")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        // Epic #37 story 37.1c: chips are Dutch literals -> catalog. Send the
                        // localized text so the sent message matches the displayed chip.
                        Button { onTap(String(localized: String.LocalizationValue(suggestion))) } label: {
                            Text(LocalizedStringKey(suggestion))
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color(.systemBackground))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: Shared coach avatar helper

private func coachAvatar(_ accentColor: Color) -> some View {
    ZStack {
        Circle()
            .fill(accentColor.opacity(0.10))
            .frame(width: 30, height: 30)
        Image(systemName: "bubble.left.fill")
            .font(.system(size: 12))
            .foregroundColor(accentColor)
    }
    .padding(.top, 14)
}

#Preview {
    ChatView(viewModel: ChatViewModel())
        .environmentObject(AppNavigationState())
}

struct WorkoutCardView: View {
    let workout: SuggestedWorkout
    /// Epic 21: Optional weather forecast for the day of this workout.
    var weatherForecast: DayForecast?
    var onSkip: (() -> Void)?
    var onAlternative: (() -> Void)?
    var onSelect: (() -> Void)?
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isProcessingAction: Bool = false

    var body: some View {
        Button(action: {
            onSelect?()
        }) {
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.displayDayLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))

                // Epic 21: Weather badge — only show if there is forecast data
                if let forecast = weatherForecast {
                    Spacer()
                    WeatherBadgeView(forecast: forecast)
                } else {
                    Spacer()
                }

                if isProcessingAction {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        Button(role: .destructive, action: {
                            isProcessingAction = true
                            onSkip?()
                            Task { @MainActor in try? await Task.sleep(nanoseconds: 5_000_000_000); isProcessingAction = false }
                        }) {
                            Label("Overslaan", systemImage: "trash")
                        }

                        Button(action: {
                            isProcessingAction = true
                            onAlternative?()
                            Task { @MainActor in try? await Task.sleep(nanoseconds: 5_000_000_000); isProcessingAction = false }
                        }) {
                            Label("Geef alternatief", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.gray)
                    }
                }
            }

            Text(workout.activityType)
                .font(.headline)

            // Sprint 17.3: Coach reasoning — why is this workout in the schedule?
            if let reasoning = workout.reasoning, !reasoning.isEmpty {
                Label(reasoning, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(themeManager.primaryAccentColor.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(workout.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

                // Statistics row: duration | TRIMP | 💧 fluid | 🍌 carbs
            WorkoutStatsRow(workout: workout)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: Color(.label).opacity(0.05), radius: 4, x: 0, y: 2)
            .opacity(isProcessingAction ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Detailed view for a single workout, intended to be shown as a bottom sheet.
struct WorkoutDetailView: View {
    let workout: SuggestedWorkout
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var planManager: TrainingPlanManager
    @State private var showingMoveSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(workout.displayDayLabel)
                                .font(.headline)
                                .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))
                            if workout.isSwapped {
                                // Story 33.2a: visual confirmation that the user moved this
                                // session themselves — prevents confusion when the day differs
                                // from the original AI suggestion.
                                Label("Verplaatst", systemImage: "arrow.triangle.swap")
                                    .font(.caption2).fontWeight(.medium)
                                    .padding(.vertical, 3).padding(.horizontal, 8)
                                    .background(themeManager.primaryAccentColor.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(themeManager.primaryAccentColor)
                            }
                        }

                        Text(workout.activityType)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top)

                    // Story 33.2a: action button to move the session to another day.
                    Button {
                        showingMoveSheet = true
                    } label: {
                        Label("Verplaats sessie", systemImage: "calendar.badge.clock")
                            .font(.subheadline).fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(themeManager.primaryAccentColor)

                    // Info section with icons
                    VStack(spacing: 16) {
                        InfoRowView(icon: "clock", title: "Duur", value: "\(workout.suggestedDurationMinutes) minuten")

                        if let trimp = workout.targetTRIMP {
                            InfoRowView(icon: "bolt.heart", title: "Doel TRIMP", value: "\(trimp)")
                        }

                        if let zone = workout.heartRateZone {
                            InfoRowView(icon: "heart.text.square", title: "Hartslagzone", value: zone)
                        }

                        if let pace = workout.targetPace {
                            InfoRowView(icon: "speedometer", title: "Doel Tempo", value: pace)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)

                    // Nutrition & Hydration section (Epic 24)
                    let profile = UserProfileService.cachedProfile()
                    if let plan = NutritionService.fuelingPlan(for: workout, profile: profile) {
                        WorkoutFuelingSectionView(plan: plan)
                    }

                    // Description section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Omschrijving")
                            .font(.headline)

                        Text(workout.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluiten") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMoveSheet) {
                MoveWorkoutSheet(workout: workout) { newDate in
                    planManager.moveWorkout(workout, to: newDate)
                    showingMoveSheet = false
                    dismiss() // also close detail — UI must show the updated order
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

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

/// Reusable row for information in the WorkoutDetailView
struct InfoRowView: View {
    let icon: String
    let title: String
    let value: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))
            // Epic #37 story 37.1c: title is a Dutch literal -> catalog; value is data.
            Text(LocalizedStringKey(title))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Epic 24 Sprint 4: Nutrition UI components

/// Compact row with training statistics at the bottom of a WorkoutCardView.
/// Shows: ⏱ duration | ⚡ TRIMP | 💧 fluid | 🍌 carbs
struct WorkoutStatsRow: View {
    let workout: SuggestedWorkout

    private var fueling: WorkoutFuelingPlan? {
        NutritionService.fuelingPlan(for: workout, profile: UserProfileService.cachedProfile())
    }

    var body: some View {
        HStack(spacing: 10) {
            if workout.suggestedDurationMinutes > 0 {
                statChip(icon: "clock", value: "\(workout.suggestedDurationMinutes) min", color: .primary)
            }

            let trimpText = workout.targetTRIMP.map { "\($0)" } ?? "-"
            statChip(icon: "bolt.heart", value: "TRIMP: \(trimpText)", color: .primary)

            if let plan = fueling {
                statChip(icon: "drop.fill", value: "\(Int(plan.fluidMl.rounded())) ml", color: .blue)
                statChip(icon: "leaf.fill", value: "\(Int(plan.carbsGram.rounded())) g", color: .green)
            }
        }
    }

    private func statChip(icon: String, value: String, color: Color) -> some View {
        Label(value, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }
}

/// Section in `WorkoutDetailView` with structured nutrition and hydration information.
struct WorkoutFuelingSectionView: View {
    let plan: WorkoutFuelingPlan

    private var interval: NutritionService.FuelingInterval {
        NutritionService.intervalBreakdown(plan: plan, every: 15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voeding & Hydratatie")
                .font(.headline)

            // Total overview
            VStack(spacing: 12) {
                InfoRowView(icon: "flame.fill",
                            title: "Verbranding",
                            value: "~\(Int(plan.totalCaloriesBurned.rounded())) kcal")
                InfoRowView(icon: "drop.fill",
                            title: "Totaal vocht",
                            value: "\(Int(plan.fluidMl.rounded())) ml")
                    .foregroundStyle(.blue)
                InfoRowView(icon: "leaf.fill",
                            title: "Totaal koolhydraten",
                            value: "\(Int(plan.carbsGram.rounded())) g")
                    .foregroundStyle(.green)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            // Interval breakdown
            VStack(alignment: .leading, spacing: 8) {
                Label("Per \(interval.intervalMinutes) minuten", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 12) {
                    intervalPill(
                        icon: "drop.fill",
                        value: "~\(Int(interval.fluidMl.rounded())) ml",
                        label: "drinken",
                        color: .blue
                    )
                    intervalPill(
                        icon: "leaf.fill",
                        value: "~\(Int(interval.carbsGram.rounded())) g",
                        label: "koolhydraten",
                        color: .green
                    )
                }

                // Timing tips
                // Epic #37 story 37.1c: phase + tips localized. Numbers are pre-formatted into
                // Strings and interpolated as %@; the optional carbs clause is its own catalog key.
                VStack(alignment: .leading, spacing: 4) {
                    timingRow(phase: "Voor", tip: String(localized: "Drink 400–600 ml water 2 uur voor de start"))
                    timingRow(phase: "Tijdens", tip: {
                        let fluidStr = "\(Int(interval.fluidMl.rounded()))"
                        var tip = String(localized: "Drink elk kwartier \(fluidStr) ml")
                        if plan.carbsGram > 20 {
                            let carbsStr = "\(Int(interval.carbsGram.rounded() * 2))"
                            tip += String(localized: "; neem elke 30 min een gelletje of \(carbsStr) g koolhydraten")
                        }
                        return tip
                    }())
                    timingRow(phase: "Na", tip: {
                        let kcalStr = "\(Int((plan.totalCaloriesBurned * 0.25).rounded()))"
                        return String(localized: "Herstel met \(kcalStr) kcal (eiwitten + koolhydraten) binnen 30 min")
                    }())
                }
                .padding(.top, 4)
            }
        }
    }

    private func intervalPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color)
                Text(value).fontWeight(.semibold)
            }
            .font(.subheadline)
            // Epic #37 story 37.1c: label/phase are Dutch literals -> catalog; value is data.
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func timingRow(phase: String, tip: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(LocalizedStringKey(phase))
                .font(.caption.weight(.semibold))
                .frame(width: 46, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(tip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - WeatherBadgeView

/// Epic 21: Compact weather badge shown on a WorkoutCardView.
/// Shows a weather icon + precipitation probability. Orange/red for bad outdoor weather.
struct WeatherBadgeView: View {
    let forecast: DayForecast

    private var badgeColor: Color {
        forecast.isRiskyForOutdoorTraining ? .orange : Color(.secondaryLabel)
    }

    private var weatherIcon: String {
        let rain = forecast.precipitationProbability
        let wind = forecast.windSpeedKmh
        if rain > 0.7 || forecast.conditionDescription.contains("regen") { return "cloud.rain.fill" }
        if rain > 0.4 { return "cloud.drizzle.fill" }
        if wind > 40 { return "wind" }
        if forecast.conditionDescription.contains("bewolkt") { return "cloud.fill" }
        if forecast.conditionDescription.contains("Mistig") { return "cloud.fog.fill" }
        if forecast.conditionDescription.contains("sneeuw") { return "snowflake" }
        if forecast.conditionDescription.contains("Onweer") { return "cloud.bolt.rain.fill" }
        return "sun.max.fill"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: weatherIcon)
                .font(.caption2)
                .foregroundColor(badgeColor)
            Text(String(format: "%.0f%%", forecast.precipitationProbability * 100))
                .font(.caption2)
                .foregroundColor(badgeColor)
            if forecast.windSpeedKmh > 30 {
                Image(systemName: "wind")
                    .font(.caption2)
                    .foregroundColor(badgeColor)
                Text(String(format: "%.0f", forecast.windSpeedKmh))
                    .font(.caption2)
                    .foregroundColor(badgeColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.12))
        .cornerRadius(6)
    }
}
