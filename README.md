# VibeCoach

Een iOS-app (SwiftUI + SwiftData) die fungeert als persoonlijke, slimme fitnesscoach. De app combineert Apple HealthKit, Strava en AI (Gemini / OpenAI / Anthropic) om trainingsschema's dynamisch en proactief bij te sturen.

---

## 🚀 Huidige Status

**Laatst gemerged — Epic #42 ✅ Always-on Dual-Source Sync (decouple van toggle) · Epic #41 ✅ Dual-Source Single-Record-of-Truth (OAuth-hardening + smart ingest) · Epic #43 ✅ UI Polish (Settings-status + Dashboard-header)**

VibeCoach is een production-ready iOS-app met fysiologisch correcte coaching, contextuele weersintelligentie (Open-Meteo), slaapfase-analyse, blessure-bewuste planning en een BYOK AI-architectuur. Testsuite: **51% code coverage** (gemeten met `xcodebuild -enableCodeCoverage YES` over de volledige unit + UI suite). Alle kritieke Services + Models zitten boven de 80% — zie [`docs/ROADMAP.md`](docs/ROADMAP.md) Epic #36 voor de per-bestand uitsplitsing.

Configureerbare Gemini-modellen zitten in Settings → AI Coach Configuratie (Epic #35). De catalogus wordt live opgehaald via de Cloudflare Worker (`/ai/models`) die op zijn beurt de Google Generative Language API bevraagt — nieuwe modellen verschijnen automatisch in de picker, geen app-release nodig. Defaults: `gemini-flash-latest` (primair) en `gemini-flash-lite-latest` (fallback).

Strava-rides met powermeter komen volledig door (Epic #40): een nightly scenePhase-pijplijn haalt 5s-streams van `cyclingPower`, `cadence` en `velocity` op via de bestaande Strava-OAuth, koppelt ze aan de juiste `ActivityRecord` via deterministische UUIDs (geen schema-migratie nodig), en draait daarna `ActivityDeduplicator` (Epic #41) en `SessionReclassifier` zodat dubbele HK+Strava-records worden samengevoegd en de zone-distributie-classificatie ook voor Strava-records werkt. Handmatig gekozen sessieTypes blijven beschermd via `manualSessionTypeOverride`.

Dual-source ingest is met Epic #41 zelfreinigend gemaakt: `FitnessDataService.ensureValidToken()` valideert + refresht het Strava-token vóór elke API-call (geen silent 401's meer), en `ActivityDeduplicator.smartInsert(_:into:)` voorkomt aan de voordeur dat een armer record (HK zonder power) een rijker record (Strava met power) overschrijft — ongeacht de volgorde waarin beide bronnen binnenkomen. De handmatige "Verwijder Dubbele Activiteiten"-knop is daarmee overbodig geworden en uit Settings verwijderd.

Met Epic #42 zijn HK + Strava daarnaast volledig **always-on**: beide sync-paden draaien concurrent via `async let` in zowel de auto-sync (`AppTabHostView`) als de manuele Settings-sync, ongeacht de bron-voorkeur. De `selectedDataSource`-toggle is hernoemd van "Primaire databron" naar "Bron-voorkeur" en bepaalt alleen nog welke bron de coach als eerste aanspreekt voor de huidige status; de sync-laag is volledig ontkoppeld. Backwards-compat: AppStorage-key + enum-rawValues ongewijzigd, dus bestaande gebruikers behouden hun toggle-stand.

Story 32.3a (Epic #32) heeft de pure-Swift pattern-detectoren neergezet: `WorkoutPatternDetector` herkent **aerobic decoupling**, **cardiac drift**, **cadence fade** en **HR-recovery** in een 5s-resampled sample-reeks, met fysiologisch onderbouwde drempels (Joe Friel / TrainingPeaks-norm) en severity-klassificering per patroon. Volledig getest (22 unit tests) zonder UI- of AI-afhankelijkheid — klaar voor consumptie door story 32.3b.

**Volgende pickup:** ⏳ Story 32.3b — annotation-pins op de `WorkoutAnalysisView`-chart + AI-context-injectie in de coach-prompt zodat patronen zichtbaar én bespreekbaar worden. Bron-voorkeur-tiebreaker in `ActivityDeduplicator` blijft open als losse follow-up.

Volledige historie en backlog: zie [`docs/ROADMAP.md`](docs/ROADMAP.md).
Technische architectuur (Dual Engine, Cloudflare Proxy, Keychain): zie [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Project-regels voor AI-assistenten: zie [`CLAUDE.md`](CLAUDE.md).

> **Talen:** UI, AI-coach-prompt en code-comments zijn momenteel Nederlandstalig (Swift-variabelen blijven Engels conform Swift-conventie). Een eventuele Engelse uitrol staat in [`docs/ROADMAP.md`](docs/ROADMAP.md) als ⏳ Epic #37 — speculatief, ~100–130u werk verspreid over UI-strings, AI-prompt-refactor, blessure-keyword-detectie en optionele comment-migratie. Geen actieve toezegging.

---

## 🛠 Installatie & Setup

1. Open `AIFitnessCoach.xcodeproj` in Xcode.
2. Kopieer in de projectmap `Secrets-template.swift` naar `Secrets.swift`.
3. Vul in `Secrets.swift` je eigen waarden in (`stravaClientID`, `stravaProxyBaseURL`, `stravaProxyToken`). Het Strava `client_secret` zit niet in de app — dat staat als Cloudflare Worker Secret in de [vibecoach-proxy](https://github.com/markclausing/vibecoach-proxy)-repo.
4. Selecteer een simulator of fysieke iPhone en druk op Run (Cmd+R).

> Voor Apple HealthKit is testen op een fysiek toestel aanbevolen.

---

## Tech Stack

| Laag | Keuze |
|------|-------|
| **Platform** | iOS 17+ (macOS + Xcode vereist om te bouwen) |
| **UI** | SwiftUI + SwiftData |
| **AI** | BYOK — Gemini Flash Latest (standaard), met UI-support voor OpenAI en Anthropic |
| **Data** | Apple HealthKit (HRV, slaap + slaapfases, workouts) + optioneel Strava OAuth2 via Cloudflare Worker |
| **Weer** | Open-Meteo API (gratis, geen API-sleutel) via CoreLocation + URLSession |
| **Achtergrond** | `HKObserverQuery` (Engine A) + `BGAppRefreshTask` (Engine B) |
| **Testen** | XCTest unit tests + XCUITest UI tests — **51% coverage** (Services + Models ≥80%, Views beperkt door SwiftUI-testbaarheid) |
| **Versiebeheer** | GitHub |

---

## Kernprincipes

- **Management by Exception:** de app waarschuwt niet bij goed gedrag — alleen bij afwijkingen. Een rode status komt altijd samen met een AI-gegenereerd herstelplan.
- **Privacy-first:** HealthKit-data blijft op device. AI-sleutels in Keychain. Strava-secret in Cloudflare Worker.
- **Type-veilig:** SwiftData met strict enums (`SportCategory`, `EventFormat`, `TrainingPhase`). Geen ruwe strings.

Zie [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) voor de Dual Engine- en proxy-architectuur.

---

## Testing Push Notifications in Simulator

Om lokale push-notificaties te testen in de iOS Simulator: maak een `test-push.apns`-bestand en sleep het naar de draaiende simulator (Drag & Drop).

```json
{
  "Simulator Target Bundle": "com.markclausing.aifitnesscoach",
  "aps": {
    "alert": {
      "title": "Doel op rood",
      "body": "Je wekelijkse Marathon-TRIMP loopt achter — bekijk je herstelplan."
    },
    "badge": 1,
    "sound": "default"
  },
  "type": "goalRisk"
}
```

> De `type`-waarde moet op de M-08 whitelist staan (`goalRisk` of `recovery_plan`), anders wordt de notificatie stil genegeerd.

---

## Bijdragen & Workflow

Zie [`CLAUDE.md`](CLAUDE.md) voor de volledige regels. Kort samengevat:

- Elke code-wijziging gaat via een branch + PR — nooit direct op `main`.
- Branchnamen: `feature/epic-{nr}-...`, `fix/...`, `security/...`, `ci/...`, `chore/...`.
- Eén fix per PR. README-updates horen bij dezelfde commit.
- Elke nieuwe feature krijgt XCTest-coverage; happy-paths krijgen een XCUITest.
