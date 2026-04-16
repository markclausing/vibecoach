import Foundation
import AuthenticationServices

@MainActor
class StravaAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    private let tokenStore: TokenStore
    private let session: NetworkSession
    private var authSession: ASWebAuthenticationSession?

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

    /// Start the OAuth flow
    func authenticate() {
        let clientId = Secrets.stravaClientID
        let callbackScheme = "aifitnesscoach"

        let authURLString = "https://www.strava.com/oauth/mobile/authorize?client_id=\(clientId)&redirect_uri=\(callbackScheme)://localhost&response_type=code&approval_prompt=auto&scope=activity:read_all,profile:read_all"

        guard let authURL = URL(string: authURLString) else {
            self.authError = "Invalid Authorization URL"
            return
        }

        self.authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                Task { @MainActor in
                    self.authError = "Authenticatie geannuleerd of mislukt: \(error.localizedDescription)"
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                Task { @MainActor in
                    self.authError = "Geen geldige autorisatiecode ontvangen van Strava."
                }
                return
            }

            // Nu we de code hebben, wissel hem om voor tokens
            Task {
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
