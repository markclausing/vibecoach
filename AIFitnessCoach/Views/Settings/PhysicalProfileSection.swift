import SwiftUI

struct PhysicalProfileEditView: View {
    var body: some View {
        Form {
            PhysicalProfileSection()
        }
        .navigationTitle("Fysiologisch Profiel")
    }
}

// MARK: - Epic 24 Sprint 2: Physiological Profile Section

/// Shows and manages the user's physiological profile.
/// Age and sex are read-only (come from the HealthKit Health app).
/// Weight and height are editable and are synchronised with HealthKit.
struct PhysicalProfileSection: View {
    // The manager is held as a property so healthStore is not deallocated immediately.
    private let hkManager = HealthKitManager()
    private var profileService: UserProfileService { UserProfileService(healthStore: hkManager.healthStore) }

    // Currently loaded profile
    @State private var profile: UserPhysicalProfile?

    // Editable fields (as String for TextField)
    @State private var weightInput: String = ""
    @State private var heightInput: String = ""

    // UI state
    @State private var isLoading     = true
    @State private var isSaving      = false
    @State private var saveMessage: String?
    /// .savedToHealthKit → green, .savedLocallyOnly → orange
    @State private var saveResult: UserProfileService.SaveResult?
    /// Timestamp of the last successful HealthKit refresh — for the sync indicator.
    @State private var lastRefreshed: Date?

    /// Coach notice on profile change — set once into the very next AI prompt.
    @AppStorage("vibecoach_profileUpdateNote") private var profileUpdateNote: String = ""

    // Detect whether the user changed anything compared to the loaded profile
    private var hasChanges: Bool {
        guard let p = profile else { return false }
        return weightInput != String(format: "%.1f", p.weightKg)
            || heightInput != String(format: "%.0f", p.heightCm)
    }

    var body: some View {
        Section(
            header: Text("Fysiologisch Profiel"),
            footer: profileFooter
        ) {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 6)
                    Text("Profiel ophalen via HealthKit…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else {
                // Sync indicator — shows the timestamp of the last HealthKit refresh
                if let ts = lastRefreshed {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Gesynchroniseerd om \(ts, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await loadProfile() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                Text("Ververs")
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Age — read-only via HealthKit
                profileRow(
                    icon: "person.circle",
                    iconColor: .blue,
                    label: "Leeftijd",
                    value: profile.map { "\($0.ageYears) " + String(localized: "jaar") } ?? String(localized: "Onbekend"),
                    isReadOnly: true
                )

                // Sex — read-only via HealthKit
                profileRow(
                    icon: "figure.stand",
                    iconColor: .indigo,
                    label: "Geslacht",
                    value: profile.map { sexLabel($0.sex) } ?? String(localized: "Onbekend"),
                    isReadOnly: true
                )

                // Weight — editable
                editableRow(
                    icon: "scalemass",
                    iconColor: .orange,
                    label: "Gewicht",
                    unit: "kg",
                    binding: $weightInput,
                    source: profile?.weightSource
                )

                // Height — editable
                editableRow(
                    icon: "ruler",
                    iconColor: .teal,
                    label: "Lengte",
                    unit: "cm",
                    binding: $heightInput,
                    source: profile?.heightSource
                )

                // Save button (only visible when there are changes)
                if hasChanges {
                    Button {
                        saveProfile()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().padding(.trailing, 4)
                                Text("Opslaan…")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Opslaan & Sync met HealthKit")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .disabled(isSaving)
                }

                // Feedback after saving
                if let msg = saveMessage {
                    let (icon, color): (String, Color) = {
                        switch saveResult {
                        case .savedToHealthKit:   return ("checkmark.circle.fill", .green)
                        case .savedLocallyOnly:   return ("exclamationmark.circle.fill", .orange)
                        case nil:                 return ("xmark.circle.fill", .red)
                        }
                    }()
                    Label(msg, systemImage: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                }
            }
        }
        // onAppear guarantees a fresh HealthKit fetch every time the section becomes visible,
        // even when the SettingsView stays in memory (tabs). .task only runs on the first render
        // in static forms — hence the switch to onAppear.
        .onAppear { Task { await loadProfile() } }
    }

    // MARK: - Sub-views

    // Epic #37 story 37.1c: `label` is a `LocalizedStringKey` so the literal row labels
    // (Leeftijd/Geslacht/…) resolve via the String Catalog; `value` stays `String` — it's
    // dynamic data (e.g. "76.0 kg") that must render verbatim.
    /// Row for a read-only value (age, sex — come from HealthKit).
    private func profileRow(icon: String, iconColor: Color, label: LocalizedStringKey, value: String, isReadOnly: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            if isReadOnly {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Row for an editable value (weight, height).
    private func editableRow(
        icon: String,
        iconColor: Color,
        label: LocalizedStringKey,
        unit: String,
        binding: Binding<String>,
        source: UserPhysicalProfile.DataSource?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            Text(label)
            Spacer()
            TextField("0", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            // Source badge
            if let src = source {
                sourceBadge(src)
            }
        }
    }

    /// Small badge indicating where the value comes from.
    @ViewBuilder
    private func sourceBadge(_ source: UserPhysicalProfile.DataSource) -> some View {
        switch source {
        case .healthKit:
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .local:
            Image(systemName: "iphone")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .defaultValue:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private var profileFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Leeftijd en geslacht worden gelezen uit de iOS Gezondheid-app en zijn hier niet te bewerken.")
            Text("Gewicht en lengte worden gesynchroniseerd naar HealthKit zodat het hele iOS-ecosysteem up-to-date blijft.")
        }
        .font(.caption)
    }

    // MARK: - Logic

    private func loadProfile() async {
        isLoading = true

        // First explicitly request read access for the profile types.
        // For users who connected HealthKit before Epic 24, dateOfBirth,
        // biologicalSex, bodyMass and height have never been requested — iOS only shows
        // the popup once we explicitly include them in requestAuthorization here.
        await profileService.requestProfileReadAuthorization()

        let loaded = await profileService.fetchProfile()

        // Detect whether the age has changed compared to the previous fetch.
        // If so, we write a one-time coach notice that gets injected into the
        // very next AI query (via vibecoach_profileUpdateNote).
        let ageChanged = profileService.checkAndUpdateAgeCache(newAge: loaded.ageYears)
        if ageChanged {
            let bmr = Int(NutritionService.calculateBMR(profile: loaded).rounded())
            profileUpdateNote = """
            [PROFIEL BIJGEWERKT — VERPLICHTE VERMELDING]:
            De leeftijd van de gebruiker is bijgewerkt naar \(loaded.ageYears) jaar (eerder opgeslagen waarde was anders). \
            Het basaal metabolisme (BMR) is herberekend naar ~\(bmr) kcal/dag op basis van het nieuwe profiel (\(loaded.coachSummary)). \
            Vernoem dit expliciet aan het begin van je eerstvolgende Insight of antwoord: \
            "Ik heb je profiel bijgewerkt naar \(loaded.ageYears) jaar; je dagelijkse energiebehoefte (BMR) is nu ~\(bmr) kcal/dag." \
            Pas voedings- en trainingsadviezen hierop aan.
            """
        }

        await MainActor.run {
            profile       = loaded
            weightInput   = String(format: "%.1f", loaded.weightKg)
            heightInput   = String(format: "%.0f", loaded.heightCm)
            isLoading     = false
            lastRefreshed = Date()
        }
    }

    private func saveProfile() {
        guard let p = profile else { return }
        let newWeight = Double(weightInput.replacingOccurrences(of: ",", with: ".")) ?? p.weightKg
        let newHeight = Double(heightInput.replacingOccurrences(of: ",", with: ".")) ?? p.heightCm

        isSaving    = true
        saveMessage = nil
        saveResult  = nil

        Task {
            // Save each changed value and collect the results.
            // UserDefaults is always updated; HealthKit only with permission.
            var results: [UserProfileService.SaveResult] = []
            if newWeight != p.weightKg { results.append(await profileService.saveWeight(kg: newWeight)) }
            if newHeight != p.heightCm { results.append(await profileService.saveHeight(cm: newHeight)) }

            // Reload the profile so the source badges are updated
            await loadProfile()

            // Combine: if at least one value went to HealthKit → green, otherwise → orange
            let combinedResult: UserProfileService.SaveResult
            let allHealthKit = results.allSatisfy {
                if case .savedToHealthKit = $0 { return true }
                return false
            }
            let firstLocalReason: String? = results.compactMap {
                if case .savedLocallyOnly(let reason) = $0 { return reason }
                return nil
            }.first

            if allHealthKit {
                combinedResult = .savedToHealthKit
            } else {
                combinedResult = .savedLocallyOnly(firstLocalReason ?? "Lokaal opgeslagen.")
            }

            await MainActor.run {
                isSaving   = false
                saveResult = combinedResult
                switch combinedResult {
                case .savedToHealthKit:
                    saveMessage = "Opgeslagen en gesynchroniseerd met HealthKit."
                case .savedLocallyOnly(let reason):
                    saveMessage = "Lokaal opgeslagen. \(reason)"
                }
            }
        }
    }

    private func sexLabel(_ sex: BiologicalSex) -> String {
        switch sex {
        case .male:    return "Man"
        case .female:  return "Vrouw"
        case .other:   return "Divers"
        case .unknown: return "Onbekend"
        }
    }
}
