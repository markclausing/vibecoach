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

### Smart-ingest aan de voordeur (Epic 41)

Naast de scenePhase-pijplijn is er een tweede, preventieve laag: `ActivityDeduplicator.smartInsert(_:into:)` wordt aangeroepen door **alle** ingest-paden (HealthKit-sync, Strava auto-sync, Strava historical-sync). Drie-laagse check per record:

1. **Source-id idempotent** — record met dezelfde HK-uuid of Strava-id bestaat al → no-op.
2. **±5s cross-source vergelijk** — kandidaat-cluster opzoeken; als bestaand record rijker is, weiger insert. Als nieuw record rijker, vervang het bestaande.
3. **Reguliere insert** — geen conflict, gewoon toevoegen.

Resultaat: een armer HK-record overschrijft nooit een rijker Strava-record met deviceWatts, ongeacht de volgorde waarin beide bronnen binnenkomen. De handmatige "Verwijder Dubbele Activiteiten"-debug-knop (pre-Epic-41) is uit Settings verwijderd — auto-dedupe + smart-ingest dekken beide kanten af.

### `ensureValidToken()` als token-guard

`FitnessDataService.ensureValidToken()` is de centrale guard vóór elke Strava-API-call. Valideert + refresht het OAuth-token via de Cloudflare Worker bij (bijna-)expiry. Vijf interne callers (`fetchLatestActivity`, `fetchActivityById`, `fetchActivityStreams`, `fetchRecentActivities`, `fetchHistoricalActivities`) routen door deze ene functie — geen silent 401's meer verderop in de pijplijn.

### Always-on sync (Epic 42)

`AppTabHostView.performAutoSync` en `SettingsView.syncHistoricalData` draaien beide bron-paden **concurrent via `async let`**, ongeacht de `selectedDataSource`-toggle. De toggle is hernoemd naar "Bron-voorkeur" en bepaalt alleen nog welke bron de coach als eerste aanspreekt voor de huidige status; de sync-laag is volledig ontkoppeld. Bestaande gebruikers behouden hun toggle-stand (AppStorage-key + raw-values ongewijzigd).

---

## 10. Workout Pattern Detection (Epic 32)

`WorkoutPatternDetector` analyseert een 5s-resampled sample-reeks (HR + power + cadence) en herkent vier fysiologische signalen volgens Joe Friel / TrainingPeaks-drempels:

| Pattern | Wat het detecteert |
|---|---|
| **Aerobic decoupling** | HR drift bij gelijke power → aerobic ceiling overschreden |
| **Cardiac drift** | HR stijgt zonder pace-toename → vermoeidheid / dehydratie |
| **Cadence fade** | Cadence valt weg in late workout-fase → spier-fatigue signal |
| **Trage HR-recovery** | HR daalt onvoldoende tijdens een rust-pauze → onvoldoende parasympatisch herstel (zie §12) |

Detectie wordt **gegated op persoonlijke HR-zones** (Epic 44): cardiac drift triggert alleen in Z1-Z3 (Z4/Z5-drift is verwacht). HR-recovery is in Epic #47 herschreven naar pauze-gebaseerde detectie met `referenceHR`-schaling — zie §12 voor de details. Decoupling en cadence fade nemen geen profiel-input.

`WorkoutAnalysisView` rendert significante patronen als `PointMark`-pins op de HR-chart + chip-row + "Coach-analyse"-card met een 3-zin Gemini-synthese (gecached per workout, geen herhaalde API-calls). Patronen uit recente workouts (`WorkoutHistoryContextBuilder`, Epic 45) worden ook in de chat-coach-prompt geïnjecteerd zodat de coach er proactief naar refereert bij plan-aanpassingen.

---

## 11. CI Pipeline (Epic 46)

GitHub Actions draait twee workflows op elke push naar `main` en elke PR:

### `iOS CI` — 4-job DAG

```
┌─ SwiftLint        (parallel, geen needs)
├─ Unit Tests ──────┬─ UI Tests
└──────────────────┴─ Coverage Report
```

- **`SwiftLint`** — `swiftlint --strict` op `.swiftlint.yml`-config. 938→0 violations baseline; 1 nieuwe violation breekt CI.
- **`Unit Tests`** — `xcodebuild test -only-testing:AIFitnessCoachTests -enableCodeCoverage YES`. xcresult als artifact (7d).
- **`UI Tests`** — `-only-testing:AIFitnessCoachUITests -parallel-testing-enabled NO`. Sequentieel om xctrunner-clone-flakiness te vermijden (Epic 46.4 root-cause). xcresult + CoreSimulator-logs als artifacts (14d).
- **`Coverage Report`** — `needs: [unit-tests, ui-tests]`. `scripts/coverage-report.py` mergt beide xcresults per-file (max-coverage approximatie) en genereert per-directory markdown met aggregaten (Testable / Views / Totaal).

### `CodeQL Security Analysis`

Matrix met twee talen, elk op de juiste runner:
- **Swift** op `macos-latest` met manuele `xcodebuild clean build`.
- **Actions** op `ubuntu-latest` (10× goedkoper) — pure YAML-statische-analyse op workflow-files.

### Concurrency

Beide workflows hebben `concurrency: ${{ github.workflow }}-${{ github.ref }}` met `cancel-in-progress: true` — force-pushes op een PR-branch cancelen oudere in-flight runs. Bespaart runner-minuten en voorkomt rollup-verwarring.

---

## 12. HR-recovery via pauze-detectie (Epic #47)

HR-recovery is fysiologisch alleen interpreteerbaar wanneer de externe load wegvalt — een vagaal-tonus-meting tegen een continu inspanning is geen recovery, maar een willekeurige spike-naar-spike-vergelijking. De Epic 32-implementatie maakte die fout: globale piek + meet HR exact 60s later. Bij continue rides zat de gebruiker 60s na de piek alweer te trappen, dus een visuele dip van 40 BPM tijdens een korte stop kwam als "4 BPM drop" uit de detector.

### `Services/PauseDetector.swift`

Pure-Swift, AppStorage-vrij, geen framework-deps. Detecteert aaneengesloten samples waar zowel `power < 5` als `cadence < 5` (nil-waarden tellen als "geen signaal", niet als "actief") voor minimaal `minimumPauseSeconds = 45`. Pre-check: workout moet minimaal 10 samples met daadwerkelijke activiteit hebben — voorkomt dat een sport zonder beide sensoren (zwemmen) als één lange pauze wordt gezien.

Per gedetecteerde pauze levert hij een `PauseRecoveryEvent` met:
- `pauseRange`: volledige tijdspanne van de pauze
- `measurementWindow`: `min(60s, pauze-duur)` vanaf pauze-start (Optie A — eerlijk voor 45-60s-pauzes, simpeler dan pro-rata drempels)
- `hrAtPauseStart`: eerste HR-data binnen het pauze-window
- `minHRInWindow`: laagste HR die in `measurementWindow` is gezien

### `WorkoutPatternDetector.detectHeartRateRecovery` — pauze-iteratie

Itereert `PauseDetector.detect(in:)`-output, berekent per event `ratio = drop / referenceHR`, en pint de pauze met de laagste ratio (slechtste recovery — Management by Exception §1: alleen exceptions tonen, en dan over het zwakste signaal).

Drempels relatief aan `referenceHR`:
- `≥ 0.15` ratio → uitstekend, geen pin
- `0.12 – 0.15` → mild
- `0.09 – 0.12` → moderate
- `< 0.09` → significant

`referenceHR` cascade: `lactateThresholdHR` (voorkeur, fysiologisch correctste anker) → `0.88 × maxHeartRate` (gangbare LTHR/HRmax-relatie) → `referenceHRFallback = 165` (populatie-default die de oude absolute drempels reproduceert: 165 × 0.15 ≈ 25 BPM goed-grens).

### Coach-prompt — `WorkoutInsightService.RecoveryEventSummary`

Naast de pin krijgt de coach via `WorkoutInsightService.InsightContext.recoveryEvents` **alle** gedetecteerde pauze-events mee — ook de uitstekende. De system-instruction van de service vertelt de AI hoe hij ermee omgaat: een uitstekende recovery mag positief gefraamd worden ("je autonome zenuwstelsel reageerde sterk") wanneer relevant voor de patronen, een matig/slecht-event versterkt vermoeidheids-vermoedens uit andere patronen. Workouts zonder pauze (interval-tests, tempo-loops) leveren geen events op en de coach noemt het niet — geen meet-window = geen onderwerp.

### Tradeoff vs. cardiac drift

Workouts zonder pauze krijgen geen HR-recovery-signaal meer. Dat is correct gedrag, maar betekent dat de `cardiacDrift`-detector (HR-stijging tussen helft 1 en 2 bij gelijke intensiteit) nu de enige HR-only-vermoeidheids-laag is voor continue rides. Dat is bewust: drift werkt op de feitelijke fysiologische signal van Z1-Z3-aerobic-werk en is wel zinvol op continue effort, terwijl recovery alleen tijdens rust-windows fysiologisch correct gemeten kan worden.
