import SwiftUI
import SwiftData

struct GoalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]

    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(goals) { goal in
                    NavigationLink {
                        EditGoalView(goal: goal)
                    } label: {
                        GoalRowView(goal: goal)
                    }
                }
                .onDelete(perform: deleteGoals)
            }
            .navigationTitle("Mijn Doelen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddGoalView()
                    .environment(\.modelContext, modelContext)
            }
            .overlay {
                if goals.isEmpty {
                    ContentUnavailableView(
                        "Geen doelen",
                        systemImage: "target",
                        description: Text("Voeg een nieuw fitnessdoel toe om je voortgang bij te houden.")
                    )
                }
            }
        }
    }

    /// Verwijdert geselecteerde doelen uit SwiftData
    private func deleteGoals(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(goals[index])
            }
            do {
                try modelContext.save()
            } catch {
                print("Failed to save context after deleting FitnessGoal: \(error)")
            }
        }
    }
}

/// Weergave van een enkel doel in de lijst
struct GoalRowView: View {
    let goal: FitnessGoal

    var daysRemaining: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: goal.targetDate)
        return components.day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.title)
                    .font(.headline)
                    .strikethrough(goal.isCompleted, color: .secondary)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)

                Spacer()

                if goal.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    if daysRemaining >= 0 {
                        Text("\(daysRemaining) dagen")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    } else {
                        Text("Verlopen")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                }
            }

            if let sport = goal.sportCategory?.displayName, !sport.isEmpty {
                Text(sport)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            Text(goal.targetDate, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
