import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager

    // We maken de ViewModel hier aan zodat we hem kunnen delen met de DashboardView
    // voor pull-to-refresh en de ChatView als overlay.
    @StateObject private var sharedChatViewModel = ChatViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $appState.selectedTab) {
                // Tab 1: Overzicht (Dashboard & Kalender)
                DashboardView(viewModel: sharedChatViewModel)
                    .tabItem {
                        Label("Overzicht", systemImage: "house.fill")
                    }
                    .tag(AppNavigationState.Tab.dashboard)

                // Tab 2: Doelen
                GoalsListView()
                    .tabItem {
                        Label("Doelen", systemImage: "target")
                    }
                    .tag(AppNavigationState.Tab.goals)

                // Tab 3: Geheugen
                NavigationStack {
                    PreferencesListView()
                }
                .tabItem {
                    Label("Geheugen", systemImage: "brain.head.profile")
                }
                .tag(AppNavigationState.Tab.memory)

                // Tab 4: Instellingen
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Instellingen", systemImage: "gearshape.fill")
                }
                .tag(AppNavigationState.Tab.settings)
            }

            // Custom Centrale Coach Knop over de TabBar heen
            Button(action: {
                appState.showingChatSheet = true
            }) {
                Image(systemName: "message.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 5)
            }
            // De offset zorgt ervoor dat de knop precies op de balk ligt
            .offset(y: -10)
        }
        .sheet(isPresented: $appState.showingChatSheet) {
            ChatView(viewModel: sharedChatViewModel)
        }
        .onAppear {
            sharedChatViewModel.setTrainingPlanManager(planManager)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
        .environmentObject(TrainingPlanManager())
}

import SwiftData

struct DashboardView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager
    @ObservedObject var viewModel: ChatViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

    @State private var currentProfile: AthleticProfile? = nil
    private let profileManager = AthleticProfileManager()

    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            print("Kon profiel niet laden in DashboardView: \(error)")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Pull-to-Refresh Hint
                        HStack {
                            Image(systemName: "arrow.down")
                            Text("Swipe omlaag om data te evalueren")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

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
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if !latestCoachInsight.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                    Text("Coach Insight")
                                        .font(.headline)
                                }
                                Text(latestCoachInsight)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Toon progressie-indicator bij asynchrone bewerkingen
                        if viewModel.isFetchingWorkout || viewModel.isTyping {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Coach analyseert schema...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if let plan = planManager.activePlan {
                            // Hergebruik de TrainingCalendarView uit ChatView,
                            // we geven wel de viewModel callbacks door zodat de acties werken.
                            TrainingCalendarView(
                                plan: plan,
                                onSkipWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.skipWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                    // Chat niet direct openen indien gewenst om de UI rustig te houden, maar we openen hem hier wel als we
                                    // verwachten dat de gebruiker de chat loader wil zien
                                    appState.showingChatSheet = true
                                },
                                onAlternativeWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.requestAlternativeWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                    appState.showingChatSheet = true
                                }
                            )
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("Nog geen schema gepland.")
                                    .font(.headline)
                                Text("Vraag de coach om een nieuw schema te maken op basis van je doelen en data.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button("Open Chat") {
                                    appState.showingChatSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 100) // Ruimte voor de FAB padding, blijft behouden ivm de nieuwe custom button
                }
                .refreshable {
                    refreshProfileContext()
                    viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                    // Voeg een kleine vertraging toe zodat de pull-animatie niet direct wegschiet
                    // Terwijl het 'echte' wachten zichtbaar wordt via de ProgressView hierboven
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            .navigationTitle("Overzicht")
            .onChange(of: appState.targetActivityId) { oldValue, newValue in
                if let activityId = newValue {
                    refreshProfileContext()
                    viewModel.analyzeWorkout(withId: activityId, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                    appState.showingChatSheet = true
                    Task { @MainActor in
                        appState.targetActivityId = nil
                    }
                }
            }
            .onAppear {
                refreshProfileContext()
            }
        }
    }
}
