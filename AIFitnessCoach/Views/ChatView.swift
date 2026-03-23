import SwiftUI


import PhotosUI
import SwiftData

/// De hoofd SwiftUI view die de chat interface toont.
struct ChatView: View {
    /// De viewmodel die de chat status en netwerklogica beheert.
    @StateObject var viewModel: ChatViewModel = ChatViewModel()

    /// Huidige item geselecteerd vanuit de iOS Photos library.
    @State private var selectedItem: PhotosPickerItem? = nil

    /// De globale app status om notificatie-tap acties af te vangen.
    @EnvironmentObject var appState: AppNavigationState

    /// SwiftData Context voor het berekenen van het atletisch profiel.
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @State private var currentProfile: AthleticProfile? = nil

    /// Actieve gebruikersvoorkeuren uit SwiftData
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

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
                // SPRINT 6.3 - Proactieve Waarschuwing UI
                if currentProfile?.isRecoveryNeeded == true {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Let op: Je trainingsvolume is erg hoog. Neem voldoende rust.")
                            .font(.subheadline)
                            .bold()
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.8))
                    .foregroundColor(.white)
                }

                // Lijst met chatberichten
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onDismissWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.dismissWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                })
                                .id(message.id)
                            }

                            // Laadindicator
                            if viewModel.isTyping {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("Coach is aan het typen...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding()
                                .id("typingIndicator")
                            }
                        }
                        .padding()
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

                // Acties / Quick Replies
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button(action: {
                            refreshProfileContext()
                            viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                        }) {
                            HStack {
                                if viewModel.isFetchingWorkout {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "figure.run")
                                }
                                Text("Analyseer laatste training")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemBlue).opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(20)
                        }
                        .disabled(viewModel.isFetchingWorkout)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
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
                            .foregroundColor(.blue)
                            .padding(8)
                            .background(Color(.systemGray6))
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

                    Button(action: {
                        refreshProfileContext()
                        viewModel.sendMessage(contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                        selectedItem = nil
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(viewModel.inputText.isEmpty && viewModel.selectedImage == nil ? .gray : .blue)
                    }
                    .disabled(viewModel.inputText.isEmpty && viewModel.selectedImage == nil)
                }
                .padding()
            }
            .navigationTitle("AI Fitness Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink(destination: PreferencesListView()) {
                            Image(systemName: "brain.head.profile")
                        }
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
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
            }
        }
    }

    /// Setup de callback in ViewModel om gedetecteerde voorkeuren op te slaan in SwiftData
    private func setupPreferenceCallback() {
        viewModel.onNewPreferencesDetected = { [weak viewModel] detectedPrefs in
            let context = modelContext
            Task { @MainActor in
                for text in detectedPrefs {
                    // Simpele deduplicatie (optioneel, let op exact matching)
                    let newPref = UserPreference(preferenceText: text)
                    context.insert(newPref)
                }
                try? context.save()
            }
        }
    }
}

/// Een herbruikbare view component die een enkel chatbericht tekent.
struct MessageBubble: View {
    /// Het bericht dat getoond moet worden.
    let message: ChatMessage

    // Geef een onDismiss actie door om de chatview te laten weten dat er een actie op de kalender plaatsvond
    var onDismissWorkout: ((SuggestedWorkout) -> Void)?

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

                if let plan = message.suggestedPlan {
                    TrainingCalendarView(plan: plan, onDismissWorkout: onDismissWorkout)
                        .padding(12)
                        .background(Color(.systemGray5))
                        .cornerRadius(16)
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .padding(12)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isUser ? .white : .primary)
                        .cornerRadius(16)
                }
            }

            if !isUser { Spacer() }
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(AppNavigationState())
}


/// Een visuele component om een trainingsschema voor 7 dagen te tonen op basis van Gemini JSON output.
struct TrainingCalendarView: View {
    let plan: SuggestedTrainingPlan

    // Bijvoorbeeld een callback als we een training willen wegdrukken of aanpassen
    var onDismissWorkout: ((SuggestedWorkout) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jouw Plan voor de komende 7 dagen")
                .font(.headline)

            Text(plan.motivation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(plan.workouts) { workout in
                        WorkoutCardView(workout: workout, onDismiss: {
                            onDismissWorkout?(workout)
                        })
                    }
                }
                .padding(.horizontal, 4) // voor schaduw clips
            }
        }
    }
}

struct WorkoutCardView: View {
    let workout: SuggestedWorkout
    var onDismiss: (() -> Void)?

    @State private var isDismissing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.dateOrDay)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Spacer()

                if isDismissing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: {
                        isDismissing = true
                        onDismiss?()
                        // Reset na een korte tijd voor de zekerheid als het mislukt
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            isDismissing = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }

            Text(workout.activityType)
                .font(.headline)

            Text(workout.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                if workout.suggestedDurationMinutes > 0 {
                    Label("\(workout.suggestedDurationMinutes) min", systemImage: "clock")
                        .font(.caption2)
                }

                let trimpText = workout.targetTRIMP != nil ? "\(workout.targetTRIMP!)" : "-"
                Label("TRIMP: \(trimpText)", systemImage: "bolt.heart")
                    .font(.caption2)
            }
        }
        .padding()
        .frame(width: 180, height: 160)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .opacity(isDismissing ? 0.5 : 1.0)
    }
}
