# ADR 001: Gebruik van Keychain voor API Tokens

## Status
Geaccepteerd

## Context
Voor de introductie van Sprint 4.2 (Externe API's voor Strava en Intervals.icu) moet de app de OAuth API tokens van gebruikers veilig opslaan.
De twee meest voor de hand liggende opties binnen het Apple ecosysteem zijn `UserDefaults` (vaak benaderd via `@AppStorage` in SwiftUI) en de `Keychain`.

`UserDefaults` is eenvoudig in gebruik, maar alle opgeslagen data (zoals strings en integers) is onversleuteld in het bestandssysteem van het iOS apparaat aanwezig. Dit maakt het kwetsbaar, zeker bij jailbroken apparaten of bij fysieke toegang via een backup.

De `Keychain` is de native, ingebouwde oplossing van Apple ontworpen voor het versleuteld opslaan van kleine stukjes gevoelige data, zoals wachtwoorden, certificaten en in dit geval OAuth tokens.

## Beslissing
We kiezen ervoor om de `Keychain` te gebruiken voor alle API tokens, secret keys en andere gevoelige gebruikersdata. We zullen een simpele `KeychainService` wrapper bouwen in Swift om de interactie met de C-based Security framework API te moderniseren.
Daarnaast ontwerpen we een `TokenStore` protocol, zodat we voor onze XCTest suite een in-memory mock kunnen injecteren. Echte Keychain operaties in XCTest (zonder host app) kunnen namelijk falen met een entitlement error (`errSecMissingEntitlement` -34018).

## Gevolgen
- **Positief:** Maximale beveiliging van gebruikersdata conform Apple's richtlijnen.
- **Positief:** Integratie met test-driven development (TDD) via protocol-oriented programming (het `TokenStore` protocol).
- **Negatief:** Een lichte toename in de complexiteit van de codebase vergeleken met het gebruik van de simpele `@AppStorage` property wrapper in SwiftUI. Views moeten tokens ophalen of wegschrijven via asynchrone / state-beheerde viewmodels in plaats van directe bindings.
