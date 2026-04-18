import SwiftUI
import PhotosUI
import SwiftData

/// De hoofd SwiftUI view die de chat interface toont.
struct ChatView: View {
    /// De viewmodel die de chat status en netwerklogica beheert.
    @ObservedObject var viewModel: ChatViewModel

    /// Huidige item geselecteerd vanuit de iOS Photos library.
    @State private var selectedItem: PhotosPickerItem? = nil

    /// De globale app status om notificatie-tap acties af te vangen.
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var themeManager: ThemeManager

    /// SwiftData Context voor het berekenen van het atletisch profiel.
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @State private var currentProfile: AthleticProfile? = nil

    /// Actieve gebruikersvoorkeuren uit SwiftData
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

    /// Bijhouden of de gebruiker de overtraining-waarschuwingsbanner heeft weggedrukt.
    @State private var warningDismissed = false

    private let profileManager = AthleticProfileManager()

    /// Werkt het actuele profiel bij vanuit SwiftData.
    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            print("Kon profiel niet laden in ChatView: \(error)")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Epic 20: BYOK — toon lege staat als er geen API-sleutel is geconfigureerd.
                if !viewModel.hasAPIKey {
                    NoAPIKeyView()
                } else {

                // SPRINT 6.3 - Proactieve Waarschuwing UI (compacter + dismissable)
                if currentProfile?.isRecoveryNeeded == true && !warningDismissed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Trainingsvolume te hoog — neem rust.")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                warningDismissed = true
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .overlay(Color.orange.opacity(0.10))
                    .foregroundStyle(.primary)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Lijst met chatberichten
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onSkipWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.skipWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                }, onAlternativeWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.requestAlternativeWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                }, onRetry: {
                                    refreshProfileContext()
                                    viewModel.retryLastMessage(contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                })
                                .id(message.id)
                            }

                            // Laadindicator (toont retry-status als de server overbelast is)
                            if viewModel.isTyping {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 8)
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
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .onChange(of: viewModel.messages) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isTyping) { _, isTyping in
                        if isTyping {
                            withAnimation {
                                proxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                    }
                }

                // Geselecteerde afbeelding preview (indien aanwezig)
                if let image = viewModel.selectedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            viewModel.clearImage()
                            selectedItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Divider()

                // Onderste invoerbalk voor tekst en foto's
                HStack(alignment: .bottom, spacing: 12) {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundStyle(themeManager.primaryAccentColor)
                            .padding(8)
                            .background(themeManager.primaryAccentColor.opacity(0.1))
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

                    Button(action: {
                        refreshProfileContext()
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
            .background(themeManager.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Vraag de Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: appState.targetActivityId) { oldValue, newValue in
                if let activityId = newValue {
                    // Start de analyse en clear daarna de target uit de state zodat
                    // hij later opnieuw getriggerd kan worden indien nodig
                    refreshProfileContext()
                    viewModel.analyzeWorkout(withId: activityId, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)

                    Task { @MainActor in
                        appState.targetActivityId = nil
                    }
                }
            }
            .onAppear {
                refreshProfileContext()
                setupPreferenceCallback()
                // SPRINT 13.4: Toon het laatste coach-inzicht als welkomstbericht als de chat nog leeg is.
                // Dit zorgt dat de gebruiker na een herstelplan direct de uitleg van de coach ziet
                // zodra ze naar de Coach-tab navigeren, ook als de AI al klaar was.
                showWelcomeInsightIfNeeded()
            }
        }
    }

    /// SPRINT 13.4: Toont het opgeslagen coach-inzicht als welkomstbericht als de chat leeg is.
    /// Zo ziet de gebruiker direct de uitleg van de coach nadat ze naar de Coach-tab navigeren,
    /// ook als de AI al klaar was voordat ze de tab openden.
    private func showWelcomeInsightIfNeeded() {
        guard viewModel.messages.isEmpty else { return }
        let insight = viewModel.latestStoredInsight
        guard !insight.isEmpty else { return }
        viewModel.injectWelcomeMessage(insight)
    }

    /// Setup de callback in ViewModel om gedetecteerde voorkeuren op te slaan in SwiftData
    private func setupPreferenceCallback() {
        viewModel.onNewPreferencesDetected = { detectedPrefs in
            let context = modelContext
            Task { @MainActor in
                // Omdat activePreferences al ge-fetched is via @Query, kunnen we die gebruiken voor een check.
                let existingTexts = activePreferences.map { $0.preferenceText.lowercased() }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                var hasNew = false
                for pref in detectedPrefs {
                    let lowerText = pref.text.lowercased()

                    // Alleen toevoegen als er nog niet (exact of bijna exact) dezelfde tekst in de lijst staat
                    if !existingTexts.contains(where: { existing in
                        existing.contains(lowerText) || lowerText.contains(existing)
                    }) {
                        var parsedDate: Date? = nil
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

/// Epic 20: Lege staat die getoond wordt als er geen API-sleutel is geconfigureerd.
/// Stuurt de gebruiker rechtstreeks naar de AI Coach Configuratie in de Instellingen.
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

/// Een herbruikbare view component die een enkel chatbericht tekent.
struct MessageBubble: View {
    /// Het bericht dat getoond moet worden.
    let message: ChatMessage
    @EnvironmentObject var themeManager: ThemeManager

    // Callbacks voor de workout kaartjes
    var onSkipWorkout: ((SuggestedWorkout) -> Void)?
    var onAlternativeWorkout: ((SuggestedWorkout) -> Void)?

    /// Callback voor de 'Probeer opnieuw' knop bij foutberichten.
    var onRetry: (() -> Void)?

    /// Bepaalt of de afzender de gebruiker is (rechts uitgelijnd en blauw).
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

                // Retry-knop — alleen zichtbaar bij herstelbare foutberichten
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


/// Een visuele component om een trainingsschema voor 7 dagen te tonen op basis van Gemini JSON output.
struct TrainingCalendarView: View {
    let plan: SuggestedTrainingPlan

    var onSkipWorkout: ((SuggestedWorkout) -> Void)?
    var onAlternativeWorkout: ((SuggestedWorkout) -> Void)?

    // Optie om de weergave te bepalen (horizontaal voor chat, verticaal voor dashboard)
    var isHorizontal: Bool = false

    // Epic 21: Optionele weersverwachting voor weers-badges op trainingskaarten
    var weeklyForecast: [DayForecast] = []

    @State private var selectedWorkoutForDetail: SuggestedWorkout?

    /// Filtert trainingen uit het verleden — het schema start altijd bij vandaag.
    private var upcomingWorkouts: [SuggestedWorkout] {
        let today = Calendar.current.startOfDay(for: Date())
        return plan.workouts.filter { $0.resolvedDate >= today }
    }

    /// Zoekt de passende DayForecast op voor de datum van een workout.
    private func forecast(for workout: SuggestedWorkout) -> DayForecast? {
        let cal = Calendar.current
        return weeklyForecast.first {
            cal.isDate($0.date, inSameDayAs: workout.resolvedDate)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jouw Plan voor de komende 7 dagen")
                .font(.headline)

            if isHorizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(upcomingWorkouts) { workout in
                            WorkoutCardView(
                                workout: workout,
                                weatherForecast: forecast(for: workout),
                                onSkip: { onSkipWorkout?(workout) },
                                onAlternative: { onAlternativeWorkout?(workout) },
                                onSelect: { selectedWorkoutForDetail = workout }
                            )
                            .frame(width: 220)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                VStack(spacing: 16) {
                    ForEach(upcomingWorkouts) { workout in
                        WorkoutCardView(
                            workout: workout,
                            weatherForecast: forecast(for: workout),
                            onSkip: { onSkipWorkout?(workout) },
                            onAlternative: { onAlternativeWorkout?(workout) },
                            onSelect: { selectedWorkoutForDetail = workout }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(item: $selectedWorkoutForDetail) { workout in
            WorkoutDetailView(workout: workout)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct WorkoutCardView: View {
    let workout: SuggestedWorkout
    /// Epic 21: Optionele weersverwachting voor de dag van deze training.
    var weatherForecast: DayForecast? = nil
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

                // Epic 21: Weers-badge — alleen tonen als er voorspellingsdata is
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { isProcessingAction = false }
                        }) {
                            Label("Overslaan", systemImage: "trash")
                        }

                        Button(action: {
                            isProcessingAction = true
                            onAlternative?()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { isProcessingAction = false }
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

            // Sprint 17.3: Coach reasoning — waarom staat deze training in het schema?
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

                // Statistieken-rij: duur | TRIMP | 💧 vocht | 🍌 koolhydraten
            WorkoutStatsRow(workout: workout)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .opacity(isProcessingAction ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Gedetailleerde view voor een enkele workout, bedoeld om als bottom sheet getoond te worden.
struct WorkoutDetailView: View {
    let workout: SuggestedWorkout
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header sectie
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.displayDayLabel)
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))

                        Text(workout.activityType)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top)

                    // Info sectie met icoontjes
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

                    // Voeding & Hydratatie sectie (Epic 24)
                    let profile = UserProfileService.cachedProfile()
                    if let plan = NutritionService.fuelingPlan(for: workout, profile: profile) {
                        WorkoutFuelingSectionView(plan: plan)
                    }

                    // Omschrijving sectie
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
        }
    }
}

/// Herbruikbare regel voor informatie in de WorkoutDetailView
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
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Epic 24 Sprint 4: Voedings UI-componenten

/// Compacte rij met trainingsstatistieken onderaan een WorkoutCardView.
/// Toont: ⏱ duur | ⚡ TRIMP | 💧 vocht | 🍌 koolhydraten
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
                statChip(icon: "drop.fill",  value: "\(Int(plan.fluidMl.rounded())) ml",   color: .blue)
                statChip(icon: "leaf.fill",  value: "\(Int(plan.carbsGram.rounded())) g",  color: .green)
            }
        }
    }

    private func statChip(icon: String, value: String, color: Color) -> some View {
        Label(value, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }
}

/// Sectie in `WorkoutDetailView` met gestructureerde voedings- en hydratatie-informatie.
struct WorkoutFuelingSectionView: View {
    let plan: WorkoutFuelingPlan

    private var interval: NutritionService.FuelingInterval {
        NutritionService.intervalBreakdown(plan: plan, every: 15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voeding & Hydratatie")
                .font(.headline)

            // Totaaloverzicht
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

            // Interval-breakdown
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
                VStack(alignment: .leading, spacing: 4) {
                    timingRow(phase: "Voor",    tip: "Drink 400–600 ml water 2 uur voor de start")
                    timingRow(phase: "Tijdens", tip: "Drink elk kwartier \(Int(interval.fluidMl.rounded())) ml\(plan.carbsGram > 20 ? "; neem elke 30 min een gelletje of \(Int(interval.carbsGram.rounded() * 2)) g koolhydraten" : "")")
                    timingRow(phase: "Na",      tip: "Herstel met \(Int((plan.totalCaloriesBurned * 0.25).rounded())) kcal (eiwitten + koolhydraten) binnen 30 min")
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func timingRow(phase: String, tip: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(phase)
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

/// Epic 21: Compacte weers-badge die op een WorkoutCardView wordt getoond.
/// Toont een weericon + neerslagkans. Oranje/rood bij slecht buitenweer.
struct WeatherBadgeView: View {
    let forecast: DayForecast

    private var badgeColor: Color {
        forecast.isRiskyForOutdoorTraining ? .orange : Color(.secondaryLabel)
    }

    private var weatherIcon: String {
        let rain = forecast.precipitationProbability
        let wind = forecast.windSpeedKmh
        if rain > 0.7 || forecast.conditionDescription.contains("regen") { return "cloud.rain.fill" }
        if rain > 0.4                                                      { return "cloud.drizzle.fill" }
        if wind > 40                                                        { return "wind" }
        if forecast.conditionDescription.contains("bewolkt")               { return "cloud.fill" }
        if forecast.conditionDescription.contains("Mistig")                { return "cloud.fog.fill" }
        if forecast.conditionDescription.contains("sneeuw")                { return "snowflake" }
        if forecast.conditionDescription.contains("Onweer")                { return "cloud.bolt.rain.fill" }
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
