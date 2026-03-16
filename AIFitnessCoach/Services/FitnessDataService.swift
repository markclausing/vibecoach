import Foundation

/// Verantwoordelijk voor het ophalen van sport- en activiteitsdata van externe API's (bijv. Strava of Intervals.icu).
actor FitnessDataService {

    private let tokenStore: TokenStore

    // Dependency Injection voor de opslag van tokens
    init(tokenStore: TokenStore = KeychainService.shared) {
        self.tokenStore = tokenStore
    }

    /// Haalt de meest recente activiteit van de gebruiker op.
    /// In Sprint 4.2 retourneert deze functie tijdelijke (mock) data.
    /// - Returns: Een string representatie van een recente activiteit (bijv. voor Gemini context).
    /// - Throws: Kan een netwerk- of autorisatiefout gooien als de API keys ontbreken (in de toekomst).
    func fetchLatestActivity() async throws -> String {
        // Controleer of de gebruiker API keys heeft ingesteld in de Keychain (als concept).
        // let stravaToken = try tokenStore.getToken(forService: "StravaToken")

        // Simuleer een netwerkvertraging (0.5 seconde)
        try await Task.sleep(nanoseconds: 500_000_000)

        return "Mock rit: 50km, gem. hartslag 140, 450 TSS."
    }
}
