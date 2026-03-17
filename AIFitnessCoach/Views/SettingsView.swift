import SwiftUI

/// Beheer van externe API koppelingen en andere voorkeuren.
/// Deze view is toegankelijk via het instellingen-icoon en schrijft gegevens
/// veilig weg naar de KeychainService.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Authenticatie service voor Strava OAuth web flow
    @StateObject private var stravaAuthService = StravaAuthService()

    // UI State variabelen, gehaald uit en geschreven naar Keychain
    @State private var intervalsToken: String = ""

    @State private var feedbackMessage: String?

    // Dependency injection (voor tests of preview)
    var tokenStore: TokenStore = KeychainService.shared

    // Laden van opgeslagen waarden
    private func loadTokens() {
        stravaAuthService.checkAuthStatus()

        do {
            intervalsToken = try tokenStore.getToken(forService: "IntervalsToken") ?? ""
        } catch {
            print("SettingsView: Kon tokens niet veilig laden (\(error))")
        }
    }

    // Opslaan van ingevoerde waarden naar native Keychain
    private func saveTokens() {
        do {
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
        Form {
                Section(
                    header: Text("Strava Connectie"),
                    footer: Text("Koppel veilig met Strava via de officiële OAuth web flow. Tokens worden lokaal versleuteld opgeslagen.").font(.caption)
                ) {
                    if stravaAuthService.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Gekoppeld aan Strava")
                        }

                        Button(role: .destructive, action: {
                            stravaAuthService.logout()
                        }) {
                            Text("Koppel los (Uitloggen)")
                        }
                    } else {
                        Button(action: {
                            stravaAuthService.authenticate()
                        }) {
                            HStack {
                                Image(systemName: "figure.run.circle.fill")
                                Text("Log in met Strava")
                                    .fontWeight(.bold)
                            }
                        }
                    }

                    if let errorMsg = stravaAuthService.authError {
                        Text(errorMsg)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section(
                    header: Text("Intervals.icu Connectie"),
                    footer: Text("API sleutels worden lokaal bewaard.").font(.caption)
                ) {
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
