# VibeCoach

Een iOS-app (SwiftUI + SwiftData) die fungeert als persoonlijke, slimme fitnesscoach. De app combineert Apple HealthKit, Strava en AI (Gemini / OpenAI / Anthropic) om trainingsschema's dynamisch en proactief bij te sturen.

---

## 🚀 Huidige Status

**Laatst gemerged — Epic #40 ✅ Strava Power-Stream Ingest · Epic #41 🔄 Dual-Source Single-Record-of-Truth (kern live)**

VibeCoach is een production-ready iOS-app met fysiologisch correcte coaching, contextuele weersintelligentie (Open-Meteo), slaapfase-analyse, blessure-bewuste planning en een BYOK AI-architectuur. Testsuite: **51% code coverage** (gemeten met `xcodebuild -enableCodeCoverage YES` over de volledige unit + UI suite). Alle kritieke Services + Models zitten boven de 80% — zie [`docs/ROADMAP.md`](docs/ROADMAP.md) Epic #36 voor de per-bestand uitsplitsing.

Configureerbare Gemini-modellen zitten in Settings → AI Coach Configuratie (Epic #35). De catalogus wordt live opgehaald via de Cloudflare Worker (`/ai/models`) die op zijn beurt de Google Generative Language API bevraagt — nieuwe modellen verschijnen automatisch in de picker, geen app-release nodig. Defaults: `gemini-flash-latest` (primair) en `gemini-flash-lite-latest` (fallback).

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
