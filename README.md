# VibeCoach

Een iOS-app (SwiftUI + SwiftData) die fungeert als persoonlijke, slimme fitnesscoach. De app combineert Apple HealthKit, Strava en AI (Gemini / OpenAI / Claude / Mistral) om trainingsschema's dynamisch en proactief bij te sturen.

---

## 🚀 Huidige Status

VibeCoach is **production-ready** als persoonlijke iOS fitnesscoach. De kernfeatures:

- **Fysiologisch correcte coaching** — Vibe Score (readiness), persoonlijke HR-zones + FTP, en een patroon-detector die aerobic decoupling, cardiac drift, cadence fade en trage HR-recovery in workout-data herkent.
- **Dual-source data** — HealthKit en Strava draaien always-on naast elkaar; smart-ingest en automatische dedupe voorkomen dat een armer record (HK zonder power) een rijker record (Strava mét power) overschrijft.
- **Contextuele intelligentie** — Open-Meteo weer, slaapfase-analyse, blessure-bewuste planning.
- **BYOK AI (multi-provider)** — Gemini, OpenAI, Claude of Mistral; elke provider z'n eigen sleutel (Keychain) + model-keuze, achter één provider-agnostische client-laag.
- **Proactief & privacy-first** — Management by Exception (alleen waarschuwen bij afwijkingen), HealthKit-data blijft on-device.

**CI:** 4-job DAG (`SwiftLint` / Unit Tests / UI Tests / Coverage Report) op `macos-latest`, plus CodeQL-scan van Swift + Actions-workflows. Testsuite: **61% combined coverage op testable code** (Models 80%, Services 59%, ViewModels 59%) + 43% op `Views/` via UI-tests.

**Recent afgesloten:** Epic #53 (multi-provider BYOK — OpenAI, Claude & Mistral naast Gemini: provider-agnostische client-laag, per-provider sleutels & modellen, validatie & onboarding), #52 (workout-analyse aanscherpen — hourly weer-range, vraagloze coach-prompt, running cadens-grafiek met cross-source HK-fallback), #46 (CI-pipeline & DAG + SwiftLint-integratie), #45 (per-workout context in coach-prompt), #44 (persoonlijke HR-zones & FTP), #42 (always-on dual-source sync), #41 (single-record-of-truth dedupe), #40 (Strava power-stream ingest), #32 (deep-dive fysiologische analyse). Tech-debt-traject loopt parallel: SwiftData V1→V4 migraties, file-splits van grote modules, logger-discipline, DST-safe date math.

**Volgende pickup:** geen actieve sprint vastgepind. Open follow-ups in [`docs/ROADMAP.md`](docs/ROADMAP.md): TestFlight-deploy (46.B1), semver-versioning (46.B6), Strict Concurrency `Complete` (39.3), force-unwrap-audit. Nieuwe Epics komen pas op tafel bij een concrete pijn.

**Meer info:**
- Volledige historie en backlog → [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Architectuur (Dual Engine, dual-source pijplijn, BYOK, CI) → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Project-regels voor AI-assistenten → [`CLAUDE.md`](CLAUDE.md)

> **Talen:** UI, AI-prompt en code-comments zijn Nederlandstalig (Swift-variabelen Engels per Swift-conventie). Engelse i18n staat als ⏳ Epic #37 in de roadmap; geen actieve toezegging.

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
| **AI** | BYOK multi-provider — Gemini (default), OpenAI, Claude of Mistral; per provider eigen sleutel + model |
| **Data** | Apple HealthKit (HRV, slaap + slaapfases, workouts) + optioneel Strava OAuth2 via Cloudflare Worker |
| **Weer** | Open-Meteo API (gratis, geen API-sleutel) via CoreLocation + URLSession |
| **Achtergrond** | `HKObserverQuery` (Engine A) + `BGAppRefreshTask` (Engine B) |
| **Testen** | XCTest unit tests + XCUITest UI tests — **61% combined coverage op testable code** (Models 80%, Services 59%, ViewModels 59%) + 43% op `Views/` via UI-tests |
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
