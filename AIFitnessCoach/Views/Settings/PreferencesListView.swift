import SwiftUI
import SwiftData

// MARK: - Memory View

struct PreferencesListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("vibecoach_userName") private var userName: String = ""

    @Query(sort: \UserPreference.createdAt, order: .reverse) private var allPreferences: [UserPreference]

    @State private var selectedSegment: MemorySegment = .pins
    @State private var selectedFilter: MemoryTypeFilter = .all
    // Epic 34 Sprint 2: material overlay below the status bar once scrolled.
    @State private var isMemoryScrolled: Bool = false

    enum MemorySegment { case pins, history }
    enum MemoryTypeFilter: CaseIterable {
        case all, injury, preference, context
        // Epic #37: filter-chip labels resolved via the catalog (rendered as Text("\(label) · \(count)")).
        var label: String {
            switch self {
            case .all:        String(localized: "Alles")
            case .injury:     String(localized: "Blessure")
            case .preference: String(localized: "Voorkeur")
            case .context:    String(localized: "Context")
            }
        }
        var icon: String {
            switch self { case .all: "square.grid.2x2"; case .injury: "exclamationmark.triangle"; case .preference: "star"; case .context: "info.circle" }
        }
    }

    private var activePreferences: [UserPreference] {
        allPreferences.filter { $0.isActive && ($0.expirationDate == nil || $0.expirationDate! > Date()) }
    }

    private var historicPreferences: [UserPreference] {
        allPreferences.filter { !$0.isActive || ($0.expirationDate.map { $0 < Date() } ?? false) }
    }

    private var filteredPreferences: [UserPreference] {
        guard selectedFilter != .all else { return activePreferences }
        return activePreferences.filter { memoryType(for: $0.preferenceText) == selectedFilter }
    }

    private func countFor(_ filter: MemoryTypeFilter) -> Int {
        filter == .all ? activePreferences.count : activePreferences.filter { memoryType(for: $0.preferenceText) == filter }.count
    }

    private var userInitials: String {
        userName.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined().uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header (Epic 34 Sprint 2: avatar icon without functionality removed)
                    VStack(alignment: .leading, spacing: 4) {
                        // Epic #37: counts pre-formatted as String → %@ key matches the catalog.
                        Text("WAT IK ONTHOU · \("\(activePreferences.count)") ACTIEVE · \("\(historicPreferences.count)") VERLOPEN")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary).kerning(0.4)
                        Text("Geheugen")
                            .font(.largeTitle).fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 56)
                    .padding(.bottom, 20)

                    // ── Segmented Control
                    HStack(spacing: 0) {
                        ForEach([MemorySegment.pins, .history], id: \.self) { seg in
                            let isSelected = selectedSegment == seg
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedSegment = seg } } label: {
                                Text(seg == .pins ? String(localized: "PINS & CONTEXT") : String(localized: "HISTORIE"))
                                    .font(.caption).fontWeight(.semibold).kerning(0.3)
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemBackground))
                                .frame(width: geo.size.width / 2)
                                .offset(x: selectedSegment == .pins ? 0 : geo.size.width / 2)
                                .animation(.easeInOut(duration: 0.2), value: selectedSegment)
                        }
                    )
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                    if selectedSegment == .pins {
                        // ── Filter Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MemoryTypeFilter.allCases, id: \.self) { filter in
                                    let isSelected = selectedFilter == filter
                                    let count = countFor(filter)
                                    Button { withAnimation { selectedFilter = filter } } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: filter.icon).font(.caption2)
                                            Text("\(filter.label) · \(count)")
                                                .font(.caption).fontWeight(.semibold)
                                        }
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(isSelected ? themeManager.primaryAccentColor : Color(.systemBackground))
                                        .clipShape(Capsule())
                                        .shadow(color: Color(.label).opacity(isSelected ? 0 : 0.05), radius: 4, x: 0, y: 1)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 16)

                        // ── Preference Cards
                        if filteredPreferences.isEmpty {
                            ContentUnavailableView {
                                Label("Nog geen herinneringen", systemImage: "brain.head.profile")
                                    .foregroundStyle(themeManager.primaryAccentColor)
                            } description: {
                                Text("Vertel de coach in de chat over je blessures, voorkeuren of doelen.")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredPreferences) { pref in
                                    MemoryPreferenceCard(
                                        preference: pref,
                                        accentColor: themeManager.primaryAccentColor
                                    ) { delete(pref) }
                                }
                            }
                            .padding(.horizontal)
                        }

                    } else {
                        // ── History tab
                        if historicPreferences.isEmpty {
                            Text("Geen verlopen herinneringen.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .padding()
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(historicPreferences) { pref in
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary).font(.caption)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pref.preferenceText)
                                                .font(.subheadline).lineLimit(2)
                                            Text(pref.createdAt, formatter: memoryDateFormatter)
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    if pref.id != historicPreferences.last?.id {
                                        Divider().padding(.leading, 48)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 4
            } action: { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMemoryScrolled = newValue
                }
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeMaterial(isActive: isMemoryScrolled)
        }
    }

    private func delete(_ pref: UserPreference) {
        modelContext.delete(pref)
        try? modelContext.save()
    }
}

// MARK: - Memory type classification (keyword-based)

private enum MemoryType: Equatable { case injury, preference, context }

private func memoryType(for text: String) -> PreferencesListView.MemoryTypeFilter {
    let lower = text.lowercased()
    if lower.contains("blessure") || lower.contains("pijn") || lower.contains("last ") || lower.contains("stijf") || lower.contains("geblesseerd") || lower.contains("klacht") {
        return .injury
    } else if lower.contains("geen ") || lower.contains("nooit") || lower.contains("niet ") || lower.contains("voorkeur") || lower.contains("rustig") {
        return .preference
    }
    return .context
}

// Epic #37: badge labels resolved via the catalog (rendered verbatim on the pin cards).
private func memoryTypeStyle(for text: String) -> (label: String, color: Color, icon: String) {
    switch memoryType(for: text) {
    case .injury:     return (String(localized: "Blessure"), .orange, "exclamationmark.triangle")
    case .preference: return (String(localized: "Voorkeur"), Color(red: 0.3, green: 0.55, blue: 0.3), "star")
    case .context:    return (String(localized: "Context"), Color(red: 0.35, green: 0.55, blue: 0.85), "info.circle")
    case .all:        return (String(localized: "Context"), Color(red: 0.35, green: 0.55, blue: 0.85), "info.circle")
    }
}

// MARK: - MemoryPreferenceCard

struct MemoryPreferenceCard: View {
    let preference: UserPreference
    let accentColor: Color
    let onDelete: () -> Void

    private var typeStyle: (label: String, color: Color, icon: String) { memoryTypeStyle(for: preference.preferenceText) }
    private var isPinned: Bool { preference.expirationDate == nil }

    private var expirationBadgeLabel: String? {
        guard let exp = preference.expirationDate, exp > Date() else { return nil }
        let df = AppDateFormatters.display("d MMM")
        return "tot \(df.string(from: exp))"
    }

    private var createdLabel: String {
        let df = AppDateFormatters.display("d MMM yyyy")
        return df.string(from: preference.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Badges + menu
            HStack(spacing: 6) {
                Label(typeStyle.label, systemImage: typeStyle.icon)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(typeStyle.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(typeStyle.color.opacity(0.12))
                    .clipShape(Capsule())

                if let expLabel = expirationBadgeLabel {
                    Label(expLabel, systemImage: "calendar")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                } else if isPinned {
                    Label("Vastgepind", systemImage: "star.fill")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Spacer()

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Verwijder", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
            }

            // Main text
            Text(preference.preferenceText)
                .font(.headline)
                .foregroundColor(.primary)

            // Footer
            HStack {
                Text("Onthouden op \(createdLabel)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private var memoryDateFormatter: DateFormatter { AppDateFormatters.display("d MMM yyyy") }
