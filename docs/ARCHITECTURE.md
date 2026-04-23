# VibeCoach Architectuur

Deze file beschrijft de belangrijkste technische bouwstenen. Voor projectregels en afspraken: zie [CLAUDE.md](../CLAUDE.md). Voor geleverde features: zie [ROADMAP.md](ROADMAP.md).

---

## 1. Dual Engine Architectuur (Epic 13)

VibeCoach coacht proactief zónder dat de gebruiker de app opent. Dat werkt via twee onafhankelijke achtergrond-triggers, beide lokaal op device:

### Engine A — Action Trigger
**Signaal:** een nieuwe HealthKit-workout.

- `HKObserverQuery` + `enableBackgroundDelivery` — iOS wekt de app bij iedere nieuwe workout.
- De app checkt direct of een doel op rood staat en stuurt een contextuele lokale push met deep-link naar de coach.
- Alle analyse gebeurt client-side; er is geen APNs of backend in deze flow.

### Engine B — Inaction Trigger
**Signaal:** de gebruiker zit te lang stil terwijl een doel op rood staat.

- `BGAppRefreshTask` via `BGTaskScheduler` — dagelijkse stille 24-uurs check.
- Meer dan 2 dagen inactief én een rood doel → empathische motivatienotificatie.
- De handler wordt geregistreerd in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` vóór `return true`.

### Shared: ProactiveNotificationService
- Singleton (`ProactiveNotificationService.shared`) beheert beide engines.
- Risicodata wordt gecached in `UserDefaults` vanuit `DashboardView` (`onAppear` + na refresh).
- Cooldown: maximaal **1 proactieve notificatie per doel per 24 uur**.
- Alle notificaties worden lokaal gescheduled via `UNUserNotificationCenter` — geen APNs, geen backend.

### Recovery Mode
- `requestRecoveryPlan()` bouwt automatisch een prompt met actuele TRIMP/week, wekelijks tekort en weken resterend.
- De AI produceert een concreet 7-daags bijgestuurd schema.
- De rode banner verandert na actie 3 dagen in een blauwe *"Herstelplan Actief"*-bevestiging.

---

## 2. Strava OAuth via Cloudflare Worker-Proxy

Het Strava `client_secret` zat aanvankelijk hardcoded in `Secrets.swift` — uit de IPA te extraheren door elke gebruiker die de binary kon openen. Sinds de security audit (C-01) loopt de flow via een serverless Cloudflare Worker.

### Proxy-architectuur
- **Aparte repository:** [`vibecoach-proxy`](https://github.com/markclausing/vibecoach-proxy) — Cloudflare Worker.
- **Endpoints:**
  - `POST /oauth/strava/exchange` — ruilt een authorization code voor tokens
  - `POST /oauth/strava/refresh` — ververst een verlopen access token
- **Secret storage:** het echte Strava `client_secret` staat als **Cloudflare Worker Secret** — nooit in source of IPA.
- **Client-auth:** de app authenticeert bij de Worker met een shared `X-Client-Token` header (`stravaProxyToken` in `Secrets.swift`). Niet cryptografisch sterk, maar stopt casual scraping.

### iOS-kant
- `StravaAuthService.exchangeCodeForToken(_:)` → POST naar Worker
- `FitnessDataService.refreshTokenIfNeeded()` → POST naar Worker
- `stravaClientSecret` is uit zowel `Secrets-template.swift` als `Secrets.swift` verwijderd.
- OAuth-flow voegt een random `state`-UUID toe die tegen de callback-URL wordt gevalideerd (CSRF-bescherming, H-01).

### Follow-up
App Attest / DeviceCheck als tweede factor op de Worker-auth — zodat alleen echte app-installaties kunnen bellen. Nog niet geïmplementeerd.

---

## 3. BYOK — API-Sleutels in Keychain

**BYOK-only:** de gebruiker voert zijn eigen AI-API-sleutel in (Gemini / OpenAI / Anthropic). Er is geen Secrets-fallback meer.

- Opslag via `UserAPIKeyStore` → `KeychainService` onder service-naam `VibeCoach_UserAIKey`.
- Eenmalige migratie in `AIFitnessCoachApp.init()` verplaatst bestaande `UserDefaults`-waarden naar de Keychain en wist de legacy-entry (idempotent).
- `SettingsView`, `AIProviderSettingsView`, `ChatViewModel`, `AddGoalView` lezen/schrijven uitsluitend via de Keychain.

---

## 4. App-bootstrap & Routing

```
AIFitnessCoachApp (@main)
├── @UIApplicationDelegateAdaptor AppDelegate
│   ├── BGTaskScheduler.register(...)           // Engine B handler
│   ├── UNUserNotificationCenterDelegate        // incl. M-08 whitelist
│   └── setupEngineA / scheduleEngineB          // alleen als onboarded
├── @AppStorage("hasCompletedOnboarding")       // poortwachter
├── @StateObject AppNavigationState             // tab-state + shared for AppDelegate
├── @StateObject TrainingPlanManager            // Single Source of Truth (Epic 11)
├── @StateObject ThemeManager                   // Epic 29
└── body
    └── ContentView                             // root + onboarding-routing
        ├── OnboardingView                      // eerste start
        └── AppTabHostView                      // hoofd-app (5 tabs)
            ├── DashboardView                   // Epic 13/14/16/17/18 UI
            ├── GoalsListView                   // Epic 23 detail-hub
            ├── ChatView                        // Epic 30 coach-kaarten
            ├── PreferencesListView             // "Geheugen"
            └── SettingsView
```

---

## 5. Notificatie-whitelist (M-08)

Inkomende notificatie-payloads worden gefilterd via een whitelist in `AppDelegate.isAllowedNotificationPayload(_:)`:

| `type`-waarde | Betekenis |
|---------------|-----------|
| `"goalRisk"` | Engine A / B: een doel staat op rood |
| `"recovery_plan"` | Automatisch gegenereerd herstelplan is klaar |

Alle andere payloads worden stil genegeerd — zowel in `willPresent` als `didReceive`. Regression-test: `StravaAuthServiceTests.testDenied_ActivityIdOnly_ReturnsFalse` borgt dat de oude APNs-`activityId`-branch niet terugsluipt.

---

## 6. SwiftData Strictness

- Geen ruwe strings voor categorieën — uitsluitend type-veilige enums (`SportCategory: String, Codable`, `EventFormat`, `PrimaryIntent`, `TrainingPhase`).
- Bij import vanuit HealthKit/Strava wordt ruwe data **direct bij de voordeur** gemapt naar deze enums — vóórdat iets in SwiftData belandt.
- Model-container: `[FitnessGoal, ActivityRecord, UserPreference, DailyReadiness, Symptom, UserConfiguration]`. Bij `-UITesting` launch argument draait hij in-memory.

---

## 7. Tijd & Datum

- Nooit `TimeInterval`-wiskunde voor historische/toekomstige periodes — **altijd** `Calendar.current.date(byAdding:to:)`.
- Base-building voor burndown wordt berekend vanaf `Date()`, nooit vanaf `targetDate` in de toekomst.
- Reden: zomertijd, schrikkeljaren, en bugs die vroeger zijn voorgekomen.

---

## 8. Logging & Privacy

- `os.Logger` met subsystem `com.markclausing.aifitnesscoach`, categorie per service (`FitnessDataService`, `ProactiveNotificationService`, ...).
- PII en identifiers (user-tokens, device-tokens, sample-waarden) worden getagd met `privacy: .private`.
- APNs device-token printing staat achter `#if DEBUG` met alleen de laatste 6 tekens.
- Doel: volledige `print`-migratie naar `os.Logger`. Fase 1 dekt de twee grootste services; de rest volgt in opvolg-PR's.
