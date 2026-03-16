import SwiftUI

/// Beheer van externe API koppelingen en andere voorkeuren.
/// Deze view is toegankelijk via het instellingen-icoon en schrijft gegevens
/// veilig weg naar de KeychainService.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // UI State variabelen, gehaald uit en geschreven naar Keychain
    @State private var stravaToken: String = ""
    @State private var intervalsToken: String = ""

    @State private var feedbackMessage: String?

    // Dependency injection (voor tests of preview)
    var tokenStore: TokenStore = KeychainService.shared

    // Laden van opgeslagen waarden
    private func loadTokens() {
        do {
            stravaToken = try tokenStore.getToken(forService: "StravaToken") ?? ""
            intervalsToken = try tokenStore.getToken(forService: "IntervalsToken") ?? ""
        } catch {
            print("SettingsView: Kon tokens niet veilig laden (\(error))")
        }
    }

    // Opslaan van ingevoerde waarden naar native Keychain
    private func saveTokens() {
        do {
            if !stravaToken.isEmpty {
                try tokenStore.saveToken(stravaToken, forService: "StravaToken")
            } else {
                try tokenStore.deleteToken(forService: "StravaToken")
            }

            if !intervalsToken.isEmpty {
                try tokenStore.saveToken(intervalsToken, forService: "IntervalsToken")
            } else {
                try tokenStore.deleteToken(forService: "IntervalsToken")
            }

            feedbackMessage = "Instellingen veilig opgeslagen"

            // Simuleer een feedback animatie, sluit daarna (of optioneel)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }

        } catch {
            feedbackMessage = "Opslaan mislukt."
            print("SettingsView: Kon tokens niet veilig opslaan (\(error))")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Externe Connecties"),
                    footer: Text("API sleutels worden lokaal en versleuteld in de Apple Keychain bewaard.").font(.caption)
                ) {
                    SecureField("Strava OAuth Token", text: $stravaToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Intervals.icu API Key", text: $intervalsToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let msg = feedbackMessage {
                    Section {
                        Text(msg)
                            .foregroundColor(msg == "Opslaan mislukt." ? .red : .green)
                    }
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        saveTokens()
                    }
                }
            }
            .onAppear {
                loadTokens()
            }
        }
    }
}
