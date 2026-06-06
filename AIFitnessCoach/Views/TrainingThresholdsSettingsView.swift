import SwiftUI
import HealthKit

// MARK: - Epic 44 Story 44.4: TrainingThresholdsSettingsView
//
// Detail view in Settings for the four personal thresholds (max HR, resting HR,
// LTHR, FTP). Four row cards with source badges, an edit sheet for manual entry,
// a button for automatic detection from HK history, and a Strava import button
// for FTP. Below the cards: a live zone preview (Karvonen or Friel for HR, Coggan
// for power) so the user immediately sees the effect of a change.

struct TrainingThresholdsSettingsView: View {

    @EnvironmentObject var themeManager: ThemeManager

    @State private var profile: UserPhysicalProfile = UserProfileService.cachedProfile()
    @State private var editingKind: ThresholdKind?
    @State private var feedbackMessage: String?
    @State private var isDetecting: Bool = false
    @State private var isImportingFTP: Bool = false

    private let estimator = PhysiologicalThresholdService()
    private let fitnessDataService = FitnessDataService()

    enum ThresholdKind: String, Identifiable, CaseIterable {
        case maxHR, restingHR, lthr, ftp
        var id: String { rawValue }

        // Epic #37 story 37.1c: rendered via Text(kind.label) -> verbatim. "Rust HR" is the
        // only Dutch label; the rest are technical abbreviations that fall back to themselves.
        var label: String {
            switch self {
            case .maxHR:      return "Max HR"
            case .restingHR:  return String(localized: "Rust HR")
            case .lthr:       return "LTHR"
            case .ftp:        return "FTP"
            }
        }

        var unit: String {
            switch self {
            case .maxHR, .restingHR, .lthr: return "BPM"
            case .ftp:                       return "W"
            }
        }

        var icon: String {
            switch self {
            case .maxHR:      return "heart.text.square.fill"
            case .restingHR:  return "moon.stars.fill"
            case .lthr:       return "waveform.path.ecg"
            case .ftp:        return "bolt.fill"
            }
        }

        var helpText: String {
            switch self {
            case .maxHR:      return String(localized: "Hoogste hartslag tijdens een max-inspanning.")
            case .restingHR:  return String(localized: "Gemiddelde hartslag in volledige rust (ochtend, voor opstaan).")
            case .lthr:       return String(localized: "Lactate Threshold HR — hoogste hartslag die je ~30 min volhoudt.")
            case .ftp:        return String(localized: "Functional Threshold Power — vermogen dat je ~1 uur volhoudt.")
            }
        }

        var storageKey: String {
            switch self {
            case .maxHR:      return UserProfileService.maxHeartRateKey
            case .restingHR:  return UserProfileService.restingHeartRateKey
            case .lthr:       return UserProfileService.lactateThresholdHRKey
            case .ftp:        return UserProfileService.ftpKey
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Persoonlijke drempels die de coach gebruikt om jouw zones te berekenen. Laat ze leeg en de app gebruikt populatie-defaults (Tanaka voor max-HR, 60 BPM voor rust).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                thresholdsCard
                actionsCard
                zonePreviewCard

                if let msg = feedbackMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.lowercased().contains("mislukt") || msg.lowercased().contains("fout") ? .orange : .secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
        .background(themeManager.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Trainingsdrempels")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingKind) { kind in
            ThresholdEditSheet(kind: kind, profile: profile) { newValue in
                applyManualEdit(kind: kind, newValue: newValue)
            }
        }
    }

    // MARK: Cards

    private var thresholdsCard: some View {
        VStack(spacing: 0) {
            ForEach(ThresholdKind.allCases) { kind in
                thresholdRow(for: kind)
                if kind != ThresholdKind.allCases.last {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func thresholdRow(for kind: ThresholdKind) -> some View {
        let value = currentValue(for: kind)
        return HStack(spacing: 14) {
            Image(systemName: kind.icon)
                .foregroundStyle(themeManager.primaryAccentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.label).font(.subheadline.weight(.semibold))
                if let badge = sourceBadge(for: value?.source) {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Niet ingesteld")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value {
                Text("\(Int(value.value)) \(kind.unit)")
                    .font(.subheadline.monospacedDigit())
            } else {
                Text("—").font(.subheadline).foregroundStyle(.tertiary)
            }
            Button {
                editingKind = kind
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(themeManager.primaryAccentColor)
            }
            .accessibilityLabel("Wijzig \(kind.label)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                runAutoDetect()
            } label: {
                actionRow(icon: "wand.and.stars",
                          title: isDetecting ? "Bezig met detecteren…" : "Detecteer uit HK historie",
                          subtitle: "Kijkt 6 maanden terug naar je workouts en rust-HR.")
            }
            .disabled(isDetecting)

            Divider().padding(.leading, 56)

            Button {
                importFTPFromStrava()
            } label: {
                actionRow(icon: "figure.run",
                          title: isImportingFTP ? "Bezig met importeren…" : "Importeer FTP van Strava",
                          subtitle: "Gebruikt de FTP uit je Strava-profiel, indien ingevoerd.")
            }
            .disabled(isImportingFTP)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // Epic #37 story 37.1c: title/subtitle as LocalizedStringKey so the literal (and ternary-of-
    // literal) call sites localize via the catalog.
    private func actionRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(themeManager.primaryAccentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var zonePreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ZONE-PREVIEW")
                .font(.caption).foregroundStyle(.secondary).kerning(0.5)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            // Heart-rate zones: Friel-LTHR is preferred if present, otherwise Karvonen.
            if let zones = heartRateZones, !zones.isEmpty {
                zoneList(title: heartRateMethodLabel, items: zones.map {
                    "Z\($0.index) \($0.name) · \($0.lowerBPM)-\($0.upperBPM) BPM"
                })
            } else {
                // Epic #51-C4: explanation based on what is missing or physiologically
                // inconsistent, instead of one generic "set thresholds" message.
                Text(PhysiologicalThresholdValidator.emptyHRZonesExplanation(for: validatorInput))
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
            }

            Divider().padding(.leading, 14)

            if let zones = powerZones, !zones.isEmpty {
                zoneList(title: "Power-zones (Coggan)", items: zones.map { zone in
                    let bound = zone.upperWatts.map { "\(zone.lowerWatts)-\($0) W" } ?? "\(zone.lowerWatts)+ W"
                    return "Z\(zone.index) \(zone.name) · \(bound)"
                })
            } else {
                Text(PhysiologicalThresholdValidator.emptyPowerZonesExplanation(for: validatorInput))
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 14)
    }

    private func zoneList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Epic #37 story 37.1c: title resolved via the catalog (handles both the computed
            // heartRateMethodLabel and literal callers). items are zone data -> verbatim.
            Text(LocalizedStringKey(title)).font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
            ForEach(items, id: \.self) { line in
                Text(line).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Computed

    /// Maps the UI profile to the validator input. Used by the zone-card
    /// explanation and (via ThresholdEditSheet) by the live validation.
    private var validatorInput: PhysiologicalThresholdValidator.ProfileInput {
        PhysiologicalThresholdValidator.ProfileInput(
            maxHR: profile.maxHeartRate?.value,
            restingHR: profile.restingHeartRate?.value,
            lthr: profile.lactateThresholdHR?.value,
            ftp: profile.ftp?.value
        )
    }

    private var heartRateZones: [HeartRateZone]? {
        if let lthr = profile.lactateThresholdHR?.value, lthr > 0 {
            return HeartRateZoneCalculator.friel(lactateThresholdHR: lthr)
        }
        let max = profile.maxHeartRate?.value ?? 0
        let rest = profile.restingHeartRate?.value ?? 0
        guard max > 0, rest > 0, max > rest else { return nil }
        return HeartRateZoneCalculator.karvonen(maxHR: max, restingHR: rest)
    }

    private var heartRateMethodLabel: String {
        if profile.lactateThresholdHR?.value ?? 0 > 0 {
            return "HR-zones (Friel · LTHR-gebaseerd)"
        }
        return "HR-zones (Karvonen · max + rest)"
    }

    private var powerZones: [PowerZone]? {
        guard let ftp = profile.ftp?.value, ftp > 0 else { return nil }
        return PowerZoneCalculator.coggan(ftp: ftp)
    }

    private func currentValue(for kind: ThresholdKind) -> ThresholdValue? {
        switch kind {
        case .maxHR:      return profile.maxHeartRate
        case .restingHR:  return profile.restingHeartRate
        case .lthr:       return profile.lactateThresholdHR
        case .ftp:        return profile.ftp
        }
    }

    // Epic #37 story 37.1c: rendered via Text(badge) -> verbatim, so localize here.
    private func sourceBadge(for source: ThresholdSource?) -> String? {
        switch source {
        case .automatic:  return String(localized: "Auto · uit HK-historie")
        case .manual:     return String(localized: "Handmatig")
        case .strava:     return "Strava"
        case .none:       return nil
        }
    }

    // MARK: Actions

    private func applyManualEdit(kind: ThresholdKind, newValue: Double?) {
        let intent: ThresholdValue?
        if let v = newValue, v > 0 {
            intent = ThresholdValue(value: v, source: .manual)
        } else {
            intent = nil
        }

        UserProfileService.saveThreshold(intent, forKey: kind.storageKey)
        profile = UserProfileService.cachedProfile()

        // Epic #51-C3: round-trip check. JSONEncoder() rarely fails for a simple
        // ThresholdValue, but the old `try?` swallowed errors silently — the user
        // then saw "updated" while nothing was persisted. By reading back right
        // after the save we detect the mismatch.
        let persisted = UserProfileService.cachedThreshold(forKey: kind.storageKey)
        if persisted?.value != intent?.value {
            feedbackMessage = String(localized: "\(kind.label) opslaan mislukt — probeer opnieuw.")
            AppLoggers.physiologicalThreshold.error("Round-trip-check faalde voor \(kind.label, privacy: .public)")
        } else {
            feedbackMessage = String(localized: "\(kind.label) bijgewerkt.")
        }
    }

    private func runAutoDetect() {
        isDetecting = true
        feedbackMessage = nil
        Task { @MainActor in
            let run = await estimator.runAutoDetect()
            profile = UserProfileService.cachedProfile()
            isDetecting = false
            let detected = [
                run.result.maxHeartRate.map { "Max HR \(Int($0))" },
                run.result.restingHeartRate.map { "Rust \(Int($0))" },
                run.result.lactateThresholdHR.map { "LTHR \(Int($0))" }
            ].compactMap { $0 }
            if detected.isEmpty {
                feedbackMessage = String(localized: "Te weinig HK-data om drempels te schatten — log nog wat trainingen en probeer opnieuw.")
            } else {
                feedbackMessage = String(localized: "Gedetecteerd uit \(run.workoutsAnalyzed) workouts + \(run.restingDaysAnalyzed) rust-dagen: \(detected.joined(separator: ", ")). Handmatige waarden zijn niet overschreven.")
            }
        }
    }

    private func importFTPFromStrava() {
        isImportingFTP = true
        feedbackMessage = nil
        Task {
            do {
                let ftp = try await fitnessDataService.fetchAthleteFTP()
                await MainActor.run {
                    isImportingFTP = false
                    if let ftp, ftp > 0 {
                        UserProfileService.saveThreshold(
                            ThresholdValue(value: Double(ftp), source: .strava),
                            forKey: UserProfileService.ftpKey
                        )
                        profile = UserProfileService.cachedProfile()
                        feedbackMessage = String(localized: "FTP \(ftp) W geïmporteerd uit Strava.")
                    } else {
                        feedbackMessage = String(localized: "Strava heeft geen FTP in je profiel staan. Voeg 'm daar toe of vul 'm hier handmatig in.")
                    }
                }
            } catch {
                await MainActor.run {
                    isImportingFTP = false
                    feedbackMessage = String(localized: "Strava-import mislukt: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Edit-sheet

private struct ThresholdEditSheet: View {
    let kind: TrainingThresholdsSettingsView.ThresholdKind
    let profile: UserPhysicalProfile
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rawValue: String

    init(kind: TrainingThresholdsSettingsView.ThresholdKind,
         profile: UserPhysicalProfile,
         onSave: @escaping (Double?) -> Void) {
        self.kind = kind
        self.profile = profile
        self.onSave = onSave
        switch kind {
        case .maxHR:      _rawValue = State(initialValue: profile.maxHeartRate.map { String(Int($0.value)) } ?? "")
        case .restingHR:  _rawValue = State(initialValue: profile.restingHeartRate.map { String(Int($0.value)) } ?? "")
        case .lthr:       _rawValue = State(initialValue: profile.lactateThresholdHR.map { String(Int($0.value)) } ?? "")
        case .ftp:        _rawValue = State(initialValue: profile.ftp.map { String(Int($0.value)) } ?? "")
        }
    }

    /// Live validation: combines a per-field range check with cross-validation
    /// against the other thresholds in the profile. Returns the most severe issue
    /// so the UI can show one clear message instead of a list.
    private var liveIssue: PhysiologicalThresholdValidator.Issue? {
        let parsed = Double(rawValue)
        let fieldIssue = PhysiologicalThresholdValidator.validateField(validatorKind, value: parsed)
        if fieldIssue.severity == .error { return fieldIssue }

        let cross = PhysiologicalThresholdValidator.validateProfile(simulatedProfile(parsed: parsed))
        if let crossError = cross.first(where: { $0.severity == .error }) {
            return crossError
        }
        return fieldIssue.severity == .ok ? nil : fieldIssue
    }

    private var canSave: Bool {
        // Empty string = clear, always allowed. Otherwise there must be no error issue.
        guard !rawValue.isEmpty else { return true }
        return (liveIssue?.severity ?? .ok) != .error
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Waarde", text: $rawValue)
                            .keyboardType(.numberPad)
                        Text(kind.unit).foregroundStyle(.secondary)
                    }
                    if let issue = liveIssue {
                        Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .accessibilityIdentifier("threshold.issue")
                    }
                } header: {
                    Text(kind.label)
                } footer: {
                    Text(kind.helpText)
                }
            }
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        onSave(Double(rawValue))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
                ToolbarItem(placement: .destructiveAction) {
                    if !rawValue.isEmpty {
                        Button("Wissen") {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    /// Maps the view-local `ThresholdKind` to the validator enum so we don't
    /// have to maintain two parallel enums.
    private var validatorKind: PhysiologicalThresholdValidator.Kind {
        switch kind {
        case .maxHR:     return .maxHR
        case .restingHR: return .restingHR
        case .lthr:      return .lthr
        case .ftp:       return .ftp
        }
    }

    /// Builds a hypothetical profile with the raw input as the new value for
    /// `kind`; the other thresholds come from the stored profile. Feeds the
    /// cross-validation so "Max HR > Resting HR" also checks when you're currently
    /// editing the Resting HR.
    private func simulatedProfile(parsed: Double?) -> PhysiologicalThresholdValidator.ProfileInput {
        var input = PhysiologicalThresholdValidator.ProfileInput(
            maxHR: profile.maxHeartRate?.value,
            restingHR: profile.restingHeartRate?.value,
            lthr: profile.lactateThresholdHR?.value,
            ftp: profile.ftp?.value
        )
        switch kind {
        case .maxHR:     input.maxHR = parsed
        case .restingHR: input.restingHR = parsed
        case .lthr:      input.lthr = parsed
        case .ftp:       input.ftp = parsed
        }
        return input
    }
}
