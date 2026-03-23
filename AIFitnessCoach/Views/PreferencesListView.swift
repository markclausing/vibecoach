import SwiftUI
import SwiftData

struct PreferencesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserPreference.createdAt, order: .reverse) private var preferences: [UserPreference]

    var body: some View {
        List {
            if preferences.isEmpty {
                Text("Geen voorkeuren gevonden. Vertel de coach in de chat wat je wensen of blessures zijn, en hij onthoudt het hier!")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(preferences) { preference in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preference.preferenceText)
                                .font(.body)
                                .strikethrough(!preference.isActive)
                                .foregroundColor(preference.isActive ? .primary : .secondary)

                            Text("Gedetecteerd op: \(preference.createdAt, formatter: itemFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { preference.isActive },
                            set: { newValue in
                                preference.isActive = newValue
                                try? modelContext.save()
                            }
                        ))
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .navigationTitle("Coach Geheugen")
        .toolbar {
            EditButton()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(preferences[index])
            }
            try? modelContext.save()
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

#Preview {
    PreferencesListView()
        .modelContainer(for: UserPreference.self, inMemory: true)
}
