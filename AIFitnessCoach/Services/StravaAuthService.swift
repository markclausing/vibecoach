import Foundation
import AuthenticationServices

@MainActor
class StravaAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    private let tokenStore: TokenStore
    private let session: NetworkSession
    private var authSession: ASWebAuthenticationSession?

    /// CSRF-bescherming: bewaart de `state`-waarde die we meegaven aan Strava.
    /// Wordt gezet in `authenticate()` en gewist zodra de callback is afgehandeld
    /// (bij succes, fout óf state-mismatch).
    private var pendingState: String?

    @Published var authError: String?
    @Published var isAuthenticated: Bool = false

    init(tokenStore: TokenStore = KeychainService.shared, session: NetworkSession = URLSession.shared) {
        self.tokenStore = tokenStore
        self.session = session
        super.init()
        checkAuthStatus()
    }

    func checkAuthStatus() {
        if let token = try? tokenStore.getToken(forService: "StravaToken"), !token.isEmpty {
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the active window scene and the window that is not presenting anything else if possible, or just the root window.
        // We ensure we get the application window to prevent ASWebAuthenticationSession from grabbing the window
        // of a presented sheet, which causes a layout bug upon dismissal.
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return ASPresentationAnchor()
        }

        return window
    }

    /// Bouwt de Strava OAuth authorize-URL inclusief een cryptografisch random
    /// `state`-parameter (CSRF). Pure functie — geen side effects — zodat we
    /// hem in unit-tests kunnen asserten.
    static func makeAuthorizationURL(clientId: String, callbackScheme: String, state: String) -> URL? {
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://localhost"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:read_all,profile:read_all"),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    /// Valideert dat de `state`-parameter uit de callback-URL exact overeenkomt
    /// met de verwachte waarde. Retourneert `false` bij ontbrekende of afwijkende
    /// state — dat duidt op een CSRF-poging of een gemanipuleerde callback.
    static func validateCallbackState(callbackURL: URL, expectedState: String?) -> Bool {
        guard let expectedState = expectedState, !expectedState.isEmpty else { return false }
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let receivedState = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            return false
        }
        return receivedState == expectedState
    }

    /// Start the OAuth flow
    func authenticate() {
        let clientId = Secrets.stravaClientID
        let callbackScheme = "aifitnesscoach"

        // H-01: genereer per sessie een random UUID als `state`-parameter.
        // Strava stuurt deze onaangetast terug in de callback; als de waarde
        // niet matcht, is de callback niet door onze eigen flow geïnitieerd
        // en breken we de authenticatie af.
        let state = UUID().uuidString
        self.pendingState = state

        guard let authURL = Self.makeAuthorizationURL(clientId: clientId, callbackScheme: callbackScheme, state: state) else {
            self.authError = "Invalid Authorization URL"
            self.pendingState = nil
            return
        }

        self.authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                Task { @MainActor in
                    self.authError = "Authenticatie geannuleerd of mislukt: \(error.localizedDescription)"
                    self.pendingState = nil
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                Task { @MainActor in
                    self.authError = "Geen geldige autorisatiecode ontvangen van Strava."
                    self.pendingState = nil
                }
                return
            }

            // H-01: valideer de state vóórdat we de autorisatie-code vertrouwen.
            // Bij mismatch stoppen we de flow — geen token-exchange.
            Task { @MainActor in
                guard Self.validateCallbackState(callbackURL: callbackURL, expectedState: self.pendingState) else {
                    self.authError = "Beveiligingsfout: de Strava-callback is niet door onze flow geïnitieerd. Probeer opnieuw."
                    self.pendingState = nil
                    return
                }
                self.pendingState = nil
                await self.exchangeCodeForToken(code: code)
            }
        }

        self.authSession?.presentationContextProvider = self
        self.authSession?.prefersEphemeralWebBrowserSession = false // Handig zodat Safari inloggegevens van Strava evt. onthoudt
        self.authSession?.start()
    }

    func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: "https://www.strava.com/oauth/token") else {
            self.authError = "Ongeldige token URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let bodyParams = [
            "client_id": Secrets.stravaClientID,
            "client_secret": Secrets.stravaClientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]

        var components = URLComponents()
        components.queryItems = bodyParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.query?.data(using: .utf8)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.authError = "Ongeldige response van server"
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                self.authError = "Token exchange mislukt: \(httpResponse.statusCode)"
                return
            }

            let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

            // Sla op in Keychain
            try tokenStore.saveToken(tokenResponse.access_token, forService: "StravaToken")
            try tokenStore.saveToken(tokenResponse.refresh_token, forService: "StravaRefreshToken")
            try tokenStore.saveToken(String(tokenResponse.expires_at), forService: "StravaTokenExpiresAt")

            self.isAuthenticated = true
            self.authError = nil

        } catch {
            self.authError = "Fout bij token exchange: \(error.localizedDescription)"
        }
    }

    func logout() {
        do {
            try tokenStore.deleteToken(forService: "StravaToken")
            try tokenStore.deleteToken(forService: "StravaRefreshToken")
            try tokenStore.deleteToken(forService: "StravaTokenExpiresAt")
            self.isAuthenticated = false
        } catch {
            self.authError = "Kon niet uitloggen (Keychain fout)"
        }
    }
}
