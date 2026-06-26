import Foundation
import AuthenticationServices
import SwiftData

@MainActor
class StravaAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    private let tokenStore: TokenStore
    private let session: NetworkSession
    private var authSession: ASWebAuthenticationSession?

    /// CSRF protection: stores the `state` value we passed to Strava.
    /// Set in `authenticate()` and cleared once the callback is handled
    /// (on success, error or state mismatch).
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

    /// Builds the Strava OAuth authorize URL including a cryptographically random
    /// `state` parameter (CSRF). A pure function — no side effects — so we
    /// can assert it in unit tests.
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

    /// Validates that the `state` parameter from the callback URL matches the
    /// expected value exactly. Returns `false` on a missing or differing
    /// state — that indicates a CSRF attempt or a manipulated callback.
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

        // H-01: generate a random UUID per session as the `state` parameter.
        // Strava returns it unchanged in the callback; if the value
        // doesn't match, the callback was not initiated by our own flow
        // and we abort authentication.
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

            // H-01: validate the state before trusting the authorization code.
            // On mismatch we stop the flow — no token exchange.
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
        self.authSession?.prefersEphemeralWebBrowserSession = false // Handy so Safari can remember Strava login details if desired
        self.authSession?.start()
    }

    func exchangeCodeForToken(code: String) async {
        // C-01: the token exchange runs via the server-side proxy so the
        // `client_secret` does not have to be in the app binary.
        guard let url = URL(string: "\(Secrets.stravaProxyBaseURL)/oauth/strava/exchange") else {
            self.authError = "Ongeldige proxy URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(Secrets.stravaProxyToken, forHTTPHeaderField: "X-Client-Token")

        do {
            request.httpBody = try JSONEncoder().encode(["code": code])
        } catch {
            self.authError = "Fout bij opbouwen van proxy-request: \(error.localizedDescription)"
            return
        }

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

            // The proxy passes the Strava JSON schema through 1-to-1.
            let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

            // Store in the Keychain
            try tokenStore.saveToken(tokenResponse.access_token, forService: "StravaToken")
            try tokenStore.saveToken(tokenResponse.refresh_token, forService: "StravaRefreshToken")
            try tokenStore.saveToken(String(tokenResponse.expires_at), forService: "StravaTokenExpiresAt")

            self.isAuthenticated = true
            self.authError = nil

        } catch {
            self.authError = "Fout bij token exchange: \(error.localizedDescription)"
        }
    }

    func logout(modelContext: ModelContext? = nil) {
        do {
            try tokenStore.deleteToken(forService: "StravaToken")
            try tokenStore.deleteToken(forService: "StravaRefreshToken")
            try tokenStore.deleteToken(forService: "StravaTokenExpiresAt")
            self.isAuthenticated = false
            // Story 61.3 (L-9): clear remaining cleartext PHI caches in UserDefaults.
            PHIContextCache.purge()
            // Story 61.7: also clear the SwiftData PHI context cache so the
            // protected store is wiped too. Caller (SettingsView) passes its
            // modelContext; nil is a no-op (e.g. in unit tests).
            if let ctx = modelContext {
                PHIContextCache.purgeSwiftData(from: ctx)
            }
        } catch {
            self.authError = "Kon niet uitloggen (Keychain fout)"
        }
    }
}
