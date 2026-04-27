import SwiftUI
import HealthKit

// MARK: - Epic 44 Story 44.4: TrainingThresholdsSettingsView
//
// Detail-view in Settings voor de vier persoonlijke drempels (max-HR, rust-HR,
// LTHR, FTP). Vier rij-cards met source-badges, edit-sheet voor handmatig
// invoeren, een knop voor automatische detectie uit HK-historie, en een
// Strava-import-knop voor FTP. Onder de cards: een live zone-preview (Karvonen
// of Friel voor HR, Coggan voor power) zodat de gebruiker direct ziet wat
// het effect is van een wijziging.

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

        var label: String {
            switch self {
            case .maxHR:      return "Max HR"
            case .restingHR:  return "Rust HR"
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
            case .maxHR:      return "Hoogste hartslag tijdens een max-inspanning."
            case .restingHR:  return "Gemiddelde hartslag in volledige rust (ochtend, voor opstaan)."
            case .lthr:       return "Lactate Threshold HR — hoogste hartslag die je ~30 min volhoudt."
            case .ftp:        return "Functional Threshold Power — vermogen dat je ~1 uur volhoudt."
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

    private func actionRow(icon: String, title: String, subtitle: String) -> some View {
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

            // Hartslagzones: Friel-LTHR heeft voorkeur als die er is, anders Karvonen.
            if let zones = heartRateZones, !zones.isEmpty {
                zoneList(title: heartRateMethodLabel, items: zones.map {
                    "Z\($0.index) \($0.name) · \($0.lowerBPM)-\($0.upperBPM) BPM"
                })
            } else {
                Text("Stel een Max HR + Rust HR in (Karvonen) of een LTHR (Friel) om HR-zones te zien.")
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
                Text("Stel een FTP in om power-zones te zien.")
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
            Text(title).font(.caption.weight(.semibold))
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

    private func sourceBadge(for source: ThresholdSource?) -> String? {
        switch source {
        case .automatic:  return "Auto · uit HK-historie"
        case .manual:     return "Handmatig"
        case .strava:     return "Strava"
        case .none:       return nil
        }
    }

    // MARK: Actions

    private func applyManualEdit(kind: ThresholdKind, newValue: Double?) {
        if let v = newValue, v > 0 {
            UserProfileService.saveThreshold(
                ThresholdValue(value: v, source: .manual),
                forKey: kind.storageKey
            )
        } else {
            UserProfileService.saveThreshold(nil, forKey: kind.storageKey)
        }
        profile = UserProfileService.cachedProfile()
        feedbackMessage = "\(kind.label) bijgewerkt."
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
                feedbackMessage = "Te weinig HK-data om drempels te schatten — log nog wat trainingen en probeer opnieuw."
            } else {
                feedbackMessage = "Gedetecteerd uit \(run.workoutsAnalyzed) workouts + \(run.restingDaysAnalyzed) rust-dagen: \(detected.joined(separator: ", ")). Handmatige waarden zijn niet overschreven."
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
                        feedbackMessage = "FTP \(ftp) W geïmporteerd uit Strava."
                    } else {
                        feedbackMessage = "Strava heeft geen FTP in je profiel staan. Voeg 'm daar toe of vul 'm hier handmatig in."
                    }
                }
            } catch {
                await MainActor.run {
                    isImportingFTP = false
                    feedbackMessage = "Strava-import mislukt: \(error.localizedDescription)"
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Waarde", text: $rawValue)
                            .keyboardType(.numberPad)
                        Text(kind.unit).foregroundStyle(.secondary)
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
}
