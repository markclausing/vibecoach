# VibeCoach

An iOS app (SwiftUI + SwiftData) that acts as a personal, smart fitness coach. The app combines Apple HealthKit, Strava and AI (Gemini / OpenAI / Claude / Mistral) to dynamically and proactively adjust training schedules.

---

## 🚀 Current Status

VibeCoach is **production-ready** as a personal iOS fitness coach. The core features:

- **Physiologically correct coaching** — Vibe Score (readiness), personal HR zones + FTP, and a pattern detector that recognises aerobic decoupling, cardiac drift, cadence fade and slow HR recovery in workout data.
- **Dual-source data** — HealthKit and Strava run always-on side by side; smart-ingest and automatic dedupe prevent a poorer record (HK without power) from overwriting a richer record (Strava with power).
- **Contextual intelligence** — Open-Meteo weather, sleep-stage analysis, injury-aware planning.
- **BYOK AI (multi-provider)** — Gemini, OpenAI, Claude or Mistral; each provider its own key (Keychain) + live-fetched model selection, behind one provider-agnostic client layer.
- **Proactive & privacy-first** — Management by Exception (only warn on deviations), HealthKit data stays on-device.

**CI:** 4-job DAG (`SwiftLint` / Unit Tests / UI Tests / Coverage Report) on `macos-latest`, plus a CodeQL scan of Swift + Actions workflows. Test suite: **61% combined coverage on testable code** (Models 80%, Services 59%, ViewModels 59%) + 43% on `Views/` via UI tests.

**Recently completed:** Epic #56 (location-aware per-stage weather — a multi-day route gets a forecast at each stage's approximate location, derived from the goal title via a parser + geocoding + great-circle interpolation), #55 (multi-day events first-class — stage entries in the week schedule, event-window suppression + post-event recovery in the coach prompt, "treats-as-race" fix), #37 (internationalisation — multilingual UI & AI coach in NL/EN/DE/ES via a String Catalog + runtime language picker; the AI coach replies in the user's language via a `respond in {language}` directive; the whole codebase and coach prompt are now English; ~527 catalog keys), #54 (dynamic per-provider model catalog — live `/v1/models` directly with the BYOK key, chat-filtered), #53 (multi-provider BYOK — OpenAI, Claude & Mistral alongside Gemini: provider-agnostic client layer, per-provider keys & models, validation & onboarding), #52 (sharper workout analysis — hourly weather range, question-free coach prompt, running cadence chart with cross-source HK fallback), #46 (CI pipeline & DAG + SwiftLint integration), #45 (per-workout context in coach prompt), #44 (personal HR zones & FTP), #42 (always-on dual-source sync), #41 (single-record-of-truth dedupe), #40 (Strava power-stream ingest), #32 (deep-dive physiological analysis). A tech-debt track runs in parallel: SwiftData V1→V5 migrations, file splits of large modules, logger discipline, DST-safe date math.

**Next pickup:** no active sprint pinned. Open follow-ups in [`docs/ROADMAP.md`](docs/ROADMAP.md): Epic #37 tail (native DE/ES translation review, per-language UI-test pass 37.8), first-class multi-day events, TestFlight deploy (46.B1), semver versioning (46.B6), Strict Concurrency `Complete` (39.3), force-unwrap audit. New Epics only come up when there is concrete pain.

**More info:**
- Full history and backlog → [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Architecture (Dual Engine, dual-source pipeline, BYOK, CI) → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Project rules for AI assistants → [`CLAUDE.md`](CLAUDE.md)

> **Languages:** the UI and AI coach are multilingual — **NL, EN, DE, ES** — selectable in Settings (default: device language). The codebase, code comments and coach prompt are **English**; the coach replies in the user's language via a runtime `respond in {language}` directive. See the Localization section in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Remaining (Epic #37 tail): native DE/ES translation review + the doc files themselves to English.

---

## 🛠 Installation & Setup

1. Open `AIFitnessCoach.xcodeproj` in Xcode.
2. In the project folder, copy `Secrets-template.swift` to `Secrets.swift`.
3. Fill in your own values in `Secrets.swift` (`stravaClientID`, `stravaProxyBaseURL`, `stravaProxyToken`). The Strava `client_secret` is not in the app — it lives as a Cloudflare Worker Secret in the [vibecoach-proxy](https://github.com/markclausing/vibecoach-proxy) repo.
4. Select a simulator or physical iPhone and press Run (Cmd+R).

> For Apple HealthKit, testing on a physical device is recommended.

---

## Tech Stack

| Layer | Choice |
|------|-------|
| **Platform** | iOS 17+ (macOS + Xcode required to build) |
| **UI** | SwiftUI + SwiftData |
| **AI** | BYOK multi-provider — Gemini (default), OpenAI, Claude or Mistral; per-provider key + model |
| **Data** | Apple HealthKit (HRV, sleep + sleep stages, workouts) + optional Strava OAuth2 via Cloudflare Worker |
| **Weather** | Open-Meteo API (free, no API key) via CoreLocation + URLSession |
| **Background** | `HKObserverQuery` (Engine A) + `BGAppRefreshTask` (Engine B) |
| **Testing** | XCTest unit tests + XCUITest UI tests — **61% combined coverage on testable code** (Models 80%, Services 59%, ViewModels 59%) + 43% on `Views/` via UI tests |
| **Version control** | GitHub |

---

## Core Principles

- **Management by Exception:** the app does not warn on good behaviour — only on deviations. A red status always comes together with an AI-generated recovery plan.
- **Privacy-first:** HealthKit data stays on device. AI keys in Keychain. Strava secret in the Cloudflare Worker.
- **Type-safe:** SwiftData with strict enums (`SportCategory`, `EventFormat`, `TrainingPhase`). No raw strings.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the Dual Engine and proxy architecture.

---

## Testing Push Notifications in the Simulator

To test local push notifications in the iOS Simulator: create a `test-push.apns` file and drag it onto the running simulator (drag & drop).

```json
{
  "Simulator Target Bundle": "com.markclausing.aifitnesscoach",
  "aps": {
    "alert": {
      "title": "Goal in the red",
      "body": "Your weekly Marathon TRIMP is falling behind — check your recovery plan."
    },
    "badge": 1,
    "sound": "default"
  },
  "type": "goalRisk"
}
```

> The `type` value must be on the M-08 whitelist (`goalRisk` or `recovery_plan`), otherwise the notification is silently ignored.

---

## Contributing & Workflow

See [`CLAUDE.md`](CLAUDE.md) for the full rules. In short:

- Every code change goes through a branch + PR — never directly on `main`.
- Branch names: `feature/epic-{nr}-...`, `fix/...`, `security/...`, `ci/...`, `chore/...`.
- One fix per PR. README updates belong in the same commit.
- Every new feature gets XCTest coverage; happy paths get an XCUITest.
