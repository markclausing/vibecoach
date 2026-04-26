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

---

## 9. Workout Samples & Dual-Source Pijplijn (Epic 32 / 40 / 41)

Sinds Epic 32 leeft de fijngranulaire workout-data (5s-buckets met HR, power, cadence, speed, distance) los van de workout zelf — de bron-`HKWorkout` of Strava-activity wordt **niet** in SwiftData gepersisteerd. Dat scheelt een redundant model en een schema-migratie iedere keer dat een bron iets verandert; de prijs is dat we een stabiele foreign key nodig hebben om samples aan een record te koppelen.

### `WorkoutSample` — foreign-key model
- `@Model final class WorkoutSample` in `Models/WorkoutSample.swift`.
- Sleutel: `workoutUUID: UUID`. Eén `ActivityRecord` ↔ N samples (geen SwiftData-relatie, gewoon een gefilterde fetch).
- Geschreven door `WorkoutSampleStore.replaceSamples(forWorkoutUUID:)` (idempotent — eerst delete, dan insert), gelezen door `samples(forWorkoutUUID:)` en `sampleCount(forWorkoutUUID:)`.

### Deterministische UUID-brug HK ↔ Strava
HK-workouts brengen hun eigen `HKWorkout.uuid` mee; Strava-records hebben alleen een numerieke `Int64`-id. Om dezelfde `WorkoutSample`-tabel voor beide bronnen te kunnen gebruiken (Epic 40), leiden we voor Strava een UUIDv5-achtige UUID af:

- `UUID.deterministic(fromStravaID:)` — SHA256 over de Strava-id, eerste 16 bytes als UUID. Stabiel: dezelfde Strava-id geeft altijd dezelfde UUID.
- `UUID.forActivityRecordID(_:)` — centrale router: `UUID(uuidString:)` voor HK-records (de id is al een UUID-string), anders de deterministische Strava-fallback. Alle code die samples opvraagt voor een `ActivityRecord` gebruikt deze router — nergens hardcoded onderscheid op bron.

Resultaat: één tabel, twee bronnen, geen schema-migratie.

### scenePhase-pijplijn in `DashboardView`
Drie helpers draaien sequentieel in dezelfde `.task` (volgorde is bewust):

1. **`backfillStravaStreams()`** — haalt Strava `/streams` op voor de laatste 10 records zonder samples (100ms throttle), schrijft via `WorkoutSampleStore`. Na deze stap heeft elk Strava-record met powermeter zijn fijngranulaire data.
2. **`runAutoDedupe()`** — `ActivityDeduplicator.runDedupe` (Epic 41). Groepeert records op startDate (±1s strict cross-sport bypass voor mapping-issues; ±5s loose mits sport matcht), behoudt de "rijkste" via heuristiek (samples > deviceWatts > trimp > avgHR > stable id-tiebreaker). Strava-record met power wint van HK-equivalent zonder.
3. **`runSessionReclassification()`** — `SessionReclassifier.rerun` (Epic 40 story 40.4). Records die net samples kregen, krijgen nu de zone-distributie-classificatie i.p.v. de avg-HR-fallback van bij ingest. Beschermd via `ActivityRecord.manualSessionTypeOverride` — een handmatige keuze in `WorkoutAnalysisView` overleeft elke rerun.

De pijplijn is volledig idempotent: een tweede run op een schone DB doet niets. Reden voor deze volgorde: dedupe vóór reclassify scheelt classify-cycles op records die toch verwijderd worden; backfill vóór dedupe zorgt dat sample-counts kloppen voor de rijkdom-heuristiek.
