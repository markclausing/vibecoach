# VibeCoach Architecture

This file describes the main technical building blocks. For project rules and conventions, see [CLAUDE.md](../CLAUDE.md). For delivered features, see [ROADMAP.md](ROADMAP.md).

> **Interactive overview:** open [`architecture/architecture.html`](architecture/architecture.html) in a browser for a clickable version of this document (modules, dependencies, flows). The accompanying [`architecture.json`](architecture/architecture.json) contains the same data machine-readable for AI agents.
>
> Both files are **derived** from this `ARCHITECTURE.md` + the codebase — they version along with the app via `meta.appVersion` (= `CFBundleShortVersionString`) and their own `meta.docRevision`. When changing this file or the module layer in `AIFitnessCoach/`, they must be updated in the same commit. See [CLAUDE.md §7 — Architecture visualisation](../CLAUDE.md#architecture-visualisation-derived-artefacts) for the update protocol.

---

## 1. Dual Engine Architecture (Epic 13)

VibeCoach coaches proactively without the user opening the app. That works via two independent background triggers, both local on device:

### Engine A — Action Trigger
**Signal:** a new HealthKit workout.

- `HKObserverQuery` + `enableBackgroundDelivery` — iOS wakes the app on every new workout.
- The app immediately checks whether a goal is in the red and sends a contextual local push with a deep link to the coach.
- All analysis happens client-side; there is no APNs or backend in this flow.

### Engine B — Inaction Trigger
**Signal:** the user has been inactive too long while a goal is in the red.

- `BGAppRefreshTask` via `BGTaskScheduler` — a daily silent 24-hour check.
- More than 2 days inactive plus a red goal → empathetic motivation notification.
- The handler is registered in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before `return true`.

### Shared: ProactiveNotificationService
- A singleton (`ProactiveNotificationService.shared`) manages both engines.
- Risk data is cached in `UserDefaults` from `DashboardView` (`onAppear` + after refresh).
- Cooldown: at most **1 proactive notification per goal per 24 hours**.
- All notifications are scheduled locally via `UNUserNotificationCenter` — no APNs, no backend.

### Recovery Mode
- `requestRecoveryPlan()` automatically builds a prompt with the current TRIMP/week, the weekly shortfall and weeks remaining.
- The AI produces a concrete 7-day adjusted schedule.
- After action, the red banner changes for 3 days into a blue *"Recovery Plan Active"* confirmation.

---

## 2. Strava OAuth via a Cloudflare Worker Proxy

The Strava `client_secret` was initially hardcoded in `Secrets.swift` — extractable from the IPA by any user who could open the binary. Since the security audit (C-01) the flow runs via a serverless Cloudflare Worker.

### Proxy architecture
- **Separate repository:** [`vibecoach-proxy`](https://github.com/markclausing/vibecoach-proxy) — Cloudflare Worker.
- **Endpoints:**
  - `POST /oauth/strava/exchange` — exchanges an authorization code for tokens
  - `POST /oauth/strava/refresh` — refreshes an expired access token
- **Secret storage:** the real Strava `client_secret` lives as a **Cloudflare Worker Secret** — never in source or IPA.
- **Client auth:** the app authenticates to the Worker with a shared `X-Client-Token` header (`stravaProxyToken` in `Secrets.swift`). Not cryptographically strong, but stops casual scraping.

### iOS side
- `StravaAuthService.exchangeCodeForToken(_:)` → POST to the Worker
- `FitnessDataService.refreshTokenIfNeeded()` → POST to the Worker
- `stravaClientSecret` has been removed from both `Secrets-template.swift` and `Secrets.swift`.
- The OAuth flow adds a random `state` UUID that is validated against the callback URL (CSRF protection, H-01).

### Follow-up
App Attest / DeviceCheck as a second factor on the Worker auth — so only real app installations can call. Not yet implemented.

---

## 3. BYOK — API Keys in the Keychain

**BYOK-only:** the user enters their own AI API key (Gemini / OpenAI / Anthropic / Mistral). There is no Secrets fallback anymore.

- Storage via `UserAPIKeyStore` → `KeychainService`. **A separate slot per provider** (Epic #53): `serviceName(for:)` → `VibeCoach_UserAIKey_<provider>`, so an OpenAI key is not lost when temporarily switching to Claude.
- Two one-time migrations in `AIFitnessCoachApp.init()` (both idempotent): (1) `migrateFromUserDefaultsIfNeeded` — legacy `UserDefaults` value → Keychain; (2) `migrateToPerProviderKeysIfNeeded` — the legacy single key (`VibeCoach_UserAIKey`) → the Gemini slot.
- `SettingsView`, `AIProviderSettingsView`, `ChatViewModel`, `WorkoutInsightService`, `AddGoalView` read/write the slot of the **active** provider (`UserAPIKeyStore.read(for:)`). The active provider comes from `AIProvider.current()` (central `AIProvider.appStorageKey`).

### Provider-agnostic client layer (Epic #53)

Before Epic #53 the entire inference was nailed to Gemini: the "abstraction" protocol `GenerativeModelProtocol` leaned on the Google SDK type `ModelContent.Part`, and every call site built its own `GoogleGenerativeAI.GenerativeModel`. Epic #53 introduces an SDK-free layer so OpenAI, Anthropic Claude and Mistral can run behind the same contract.

- **SDK-free contract** (`ViewModels/GenerativeModelProtocol.swift`): `AIPromptPart` (`.text` / `.imageData`) replaces `ModelContent.Part`; `AIProviderError` is the unified error (overloaded/auth/contentBlocked/http/empty/decoding); `RealAIProviderClient` is a marker by which `ChatViewModel` applies the API-key gate only to live clients (mocks deliberately do not conform). `AIProviderError.isOverload(_:)` recognises both `.overloaded` and the Gemini `internalError` so the 503/429 waterfall is provider-agnostic.
- **Factory + clients** (`Services/AIModelFactory.swift`): `AIModelFactory.makeModel(provider:…)` routes per `AIProvider` to `RealGenerativeModel` (Gemini adapter, maps `AIPromptPart` → SDK), `OpenAICompatibleModelClient` (OpenAI **and** Mistral via `/v1/chat/completions`, `Bearer` auth, `response_format` for JSON mode) or `AnthropicModelClient` (`/v1/messages`, `x-api-key` + `anthropic-version`, JSON via assistant prefill `{`). Per-provider differences (system-instruction placement, JSON mode, error mapping via `AIProviderHTTP.validate`) live entirely in this layer.
- **Call sites** (`ChatViewModel`, `WorkoutInsightService`, `AddGoalView`) are now SDK-free and route via the factory; only `AIModelFactory` (the Gemini adapter) and `APIKeyValidator` still import `GoogleGenerativeAI`.
- **Model defaults per provider** (sprint B): `AIModelCatalog.builtIn(for:)` provides a curated catalog per provider (Gemini = the Worker catalog). `AIModelAppStorageKey` is provider-aware (Gemini keeps the legacy Epic #35 keys). `ChatViewModel` resolves model + key consistently via a single `currentProvider` (rebuild check, snapshot and banner use the same resolution — otherwise a rebuild loop).
- **Validation per provider** (sprint B): `APIKeyValidator.validate(_:provider:)` pings the cheapest provider model via the factory; `classify(_:)` maps both `AIProviderError` and `GenerateContentError`/`URLError`. A 4xx carries the (truncated) provider error body so the user sees the real reason.
- **UI + onboarding** (sprint C): `AIProviderSettingsView` has a key field per provider (its own Keychain slot) + a model picker. The onboarding step "Your AI" lets the user pick all four providers with a `getKeyURL` link.
- **Live model catalog per provider** (Epic #54): `ProviderModelListService` fetches `/v1/models` **directly with the user key** (OpenAI/Anthropic/Mistral) and filters to chat models; the key does not leave the device via our servers. Gemini stays on the Cloudflare Worker (`AIModelCatalogService`, our own key). Settings shows the live list with the static `AIModelCatalog.builtIn(for:)` as a safety net.
- **Status:** ✅ done — Gemini/OpenAI/Claude/Mistral are fully-fledged BYOK choices. Existing Gemini users keep their key and model choice (legacy single key migrated to the Gemini slot).

---

## 4. App Bootstrap & Routing

```
AIFitnessCoachApp (@main)
├── @UIApplicationDelegateAdaptor AppDelegate
│   ├── BGTaskScheduler.register(...)           // Engine B handler
│   ├── UNUserNotificationCenterDelegate        // incl. M-08 whitelist
│   └── setupEngineA / scheduleEngineB          // only when onboarded
├── @AppStorage("hasCompletedOnboarding")       // gatekeeper
├── @StateObject AppNavigationState             // tab state + shared for AppDelegate
├── @StateObject TrainingPlanManager            // Single Source of Truth (Epic 11)
├── @StateObject ThemeManager                   // Epic 29
└── body
    └── ContentView                             // root + onboarding routing
        ├── OnboardingView                      // first start
        └── AppTabHostView                      // main app (5 tabs)
            ├── DashboardView                   // Epic 13/14/16/17/18 UI
            ├── GoalsListView                   // Epic 23 detail hub
            ├── ChatView                        // Epic 30 coach cards
            ├── PreferencesListView             // "Memory"
            └── SettingsView
```

---

## 5. Notification whitelist (M-08)

Incoming notification payloads are filtered via a whitelist in `AppDelegate.isAllowedNotificationPayload(_:)`:

| `type` value | Meaning |
|---------------|-----------|
| `"goalRisk"` | Engine A / B: a goal is in the red |
| `"recovery_plan"` | An automatically generated recovery plan is ready |

All other payloads are silently ignored — both in `willPresent` and `didReceive`. Regression test: `StravaAuthServiceTests.testDenied_ActivityIdOnly_ReturnsFalse` ensures the old APNs `activityId` branch does not creep back in.

---

## 6. SwiftData Strictness

- No raw strings for categories — type-safe enums only (`SportCategory: String, Codable`, `EventFormat`, `PrimaryIntent`, `TrainingPhase`).
- When importing from HealthKit/Strava, raw data is mapped to these enums **right at the front door** — before anything reaches SwiftData.
- Model container: `[FitnessGoal, ActivityRecord, UserPreference, DailyReadiness, Symptom, UserConfiguration]`. With the `-UITesting` launch argument it runs in-memory.

---

## 7. Time & Date

- Never use `TimeInterval` math for historical/future periods — **always** `Calendar.current.date(byAdding:to:)`.
- Base-building for burndown is computed from `Date()`, never from `targetDate` in the future.
- Reason: daylight saving time, leap years, and bugs that occurred before.

---

## 8. Logging & Privacy

- `os.Logger` with subsystem `com.markclausing.aifitnesscoach`, a category per service (`FitnessDataService`, `ProactiveNotificationService`, ...).
- PII and identifiers (user tokens, device tokens, sample values) are tagged with `privacy: .private`.
- APNs device-token printing is behind `#if DEBUG` with only the last 6 characters.
- Goal: a full `print` migration to `os.Logger`. Phase 1 covers the two largest services; the rest follows in follow-up PRs.

---

## 9. Workout Samples & Dual-Source Pipeline (Epic 32 / 40 / 41)

Since Epic 32 the fine-grained workout data (5s buckets with HR, power, cadence, speed, distance) lives separately from the workout itself — the source `HKWorkout` or Strava activity is **not** persisted in SwiftData. That saves a redundant model and a schema migration every time a source changes something; the price is that we need a stable foreign key to link samples to a record.

### `WorkoutSample` — foreign-key model
- `@Model final class WorkoutSample` in `Models/WorkoutSample.swift`.
- Key: `workoutUUID: UUID`. One `ActivityRecord` ↔ N samples (no SwiftData relationship, just a filtered fetch).
- Written by `WorkoutSampleStore.replaceSamples(forWorkoutUUID:)` (idempotent — delete first, then insert), read by `samples(forWorkoutUUID:)` and `sampleCount(forWorkoutUUID:)`.

### Deterministic UUID bridge HK ↔ Strava
HK workouts bring their own `HKWorkout.uuid`; Strava records only have a numeric `Int64` id. To use the same `WorkoutSample` table for both sources (Epic 40), we derive a UUIDv5-like UUID for Strava:

- `UUID.deterministic(fromStravaID:)` — SHA256 over the Strava id, first 16 bytes as a UUID. Stable: the same Strava id always yields the same UUID.
- `UUID.forActivityRecordID(_:)` — central router: `UUID(uuidString:)` for HK records (the id is already a UUID string), otherwise the deterministic Strava fallback. All code that requests samples for an `ActivityRecord` uses this router — no hardcoded source distinction anywhere.

Result: one table, two sources, no schema migration.

**Cross-source cadence fallback (Epic #52).** The UUID bridge has an edge case: an Apple Watch run often also arrives as a Strava activity, and on dedupe the Strava record wins (`device_watts` → +500 in `ActivityDeduplicator.score`, because the Watch measures running power). The shown detail view then requests samples under the Strava UUID, while the Watch `stepCount` (from which running cadence is derived) lives under the HK workout UUID — cadence goes missing even though the data is in HealthKit. `WorkoutSampleService.fetchStepCadence(start:end:)` is therefore decoupled from a specific `HKWorkout`: a query on the time window alone bypasses the UUID fragmentation (HealthKit deduplicates `stepCount` across sources itself). `WorkoutAnalysisView.loadCadenceFallbackIfNeeded()` falls back to this when the stored samples contain no cadence and it is a running workout; chart, scrubber card and Coach prompt then read from a unified `cadencePoints` source (stored samples → HK fallback).

### scenePhase pipeline in `DashboardView`
Three helpers run sequentially in the same `.task` (order is deliberate):

1. **`backfillStravaStreams()`** — fetches Strava `/streams` for the last 10 records without samples (100ms throttle), writes via `WorkoutSampleStore`. After this step every Strava record with a power meter has its fine-grained data.
2. **`runAutoDedupe()`** — `ActivityDeduplicator.runDedupe` (Epic 41). Groups records by startDate (±1s strict cross-sport bypass for mapping issues; ±5s loose if the sport matches), keeps the "richest" via heuristic (samples > deviceWatts > trimp > avgHR > stable id tiebreaker). A Strava record with power beats the HK equivalent without.
3. **`runSessionReclassification()`** — `SessionReclassifier.rerun` (Epic 40 story 40.4). Records that just got samples now get the zone-distribution classification instead of the avg-HR fallback from ingest. Protected via `ActivityRecord.manualSessionTypeOverride` — a manual choice in `WorkoutAnalysisView` survives every rerun.

The pipeline is fully idempotent: a second run on a clean DB does nothing. Reason for this order: dedupe before reclassify saves classify cycles on records that get deleted anyway; backfill before dedupe ensures sample counts are correct for the richness heuristic.

### Smart-ingest at the front door (Epic 41)

Besides the scenePhase pipeline there is a second, preventive layer: `ActivityDeduplicator.smartInsert(_:into:)` is called by **all** ingest paths (HealthKit sync, Strava auto-sync, Strava historical sync). Three-layer check per record:

1. **Source-id idempotent** — a record with the same HK uuid or Strava id already exists → no-op.
2. **±5s cross-source compare** — look up the candidate cluster; if the existing record is richer, refuse the insert. If the new record is richer, replace the existing one.
3. **Regular insert** — no conflict, just add.

Result: a poorer HK record never overwrites a richer Strava record with deviceWatts, regardless of the order in which the two sources arrive. The manual "Remove Duplicate Activities" debug button (pre-Epic-41) has been removed from Settings — auto-dedupe + smart-ingest cover both sides.

### `ensureValidToken()` as token guard

`FitnessDataService.ensureValidToken()` is the central guard before every Strava API call. Validates + refreshes the OAuth token via the Cloudflare Worker on (near-)expiry. Five internal callers (`fetchLatestActivity`, `fetchActivityById`, `fetchActivityStreams`, `fetchRecentActivities`, `fetchHistoricalActivities`) route through this one function — no more silent 401s further down the pipeline.

### Always-on sync (Epic 42)

`AppTabHostView.performAutoSync` and `SettingsView.syncHistoricalData` run both source paths **concurrently via `async let`**, regardless of the `selectedDataSource` toggle. The toggle has been renamed to "Source preference" and now only determines which source the coach addresses first for the current status; the sync layer is fully decoupled. Existing users keep their toggle setting (AppStorage key + raw values unchanged).

### Deep Sync: continuous instead of one-off

`DeepSyncService.runIfNeeded()` (Services/DeepSyncService.swift:96+) was once the **one-off** 30-day historical sync. Since the fix `fix/workout-samples-loading` the "one-off completion flag" (`DeepSync.hasCompletedInitialDeepSync`) is **disabled**: it is no longer written and the guard that keyed on that flag is gone. The service now runs on every trigger (DashboardView.task and after `runHealthKitAutoSync` in AppTabHostView), but stays idempotent via the permanent `processed` UUID set in UserDefaults. Result: a workout that just arrived via auto-sync gets its samples within one view refresh — previously it hung forever on the "Deep Sync running in the background" placeholder because the flag was already true from the very first backfill.

**Ingest-revision migration (Epic #52):** the permanent `processed` set has a downside — when `WorkoutSampleService.ingestSamples` starts fetching a new signal (running cadence from `stepCount`), already-processed workouts stay on the old, incomplete sample set. `DeepSyncService.currentIngestRevision` (bumped along with such changes) is compared at launch with the stored revision; on a lower/missing revision `applyIngestRevisionMigrationIfNeeded` clears the `processed` set so all workouts in the window are re-ingested once. `replaceSamples` is idempotent, so no data loss — only temporary extra HK fetches on the next run.

### Sync visibility: one banner for three failure modes (Epic #51-F)

Previously the auto-syncs failed silently — an expired Strava token, a 429 rate limit or a closed network connection led at most to a `print()` in the Xcode console. Since Epic #51-F (F1/F2/F5) there is one central `SyncStatusBanner` on the Dashboard that — depending on the current status snapshot — shows an offline, rate-limit or error banner.

**Data path:** `AppTabHostView.runStravaAutoSync` / `runHealthKitAutoSync` write success and errors to `SyncStatusStore` (Services/SyncStatusStore.swift). The store is pure-Swift, UserDefaults-backed (Doubles for the timestamps so `@AppStorage` in the View can bind to them reactively) and explicitly filters out `.missingToken` — users without a Strava connection get no banner about a sync they never enabled. A `SyncStatusSnapshot` is the value-type input for `SyncBannerStateBuilder` (a pure function, no side effects); the builder determines which state becomes visible: **offline > rate-limited > error > nil**.

**Rate-limit cooldown (F2):** `FitnessDataService.validateHTTPResponse` detects HTTP 429, uses `StravaRateLimitParser` to compute an absolute `Date` from `Retry-After` (delta-seconds or HTTP date) — fallback 15 min, clock-skew protection for stale date headers — and persists it in `StravaRateLimitStore`. `ensureValidToken()` checks before every request whether the cooldown is still active and throws `.rateLimited` directly without touching the network; this prevents a retry storm right after launch from flickering a banner or forcing a cascading 429. A successful 2xx response clears the cooldown automatically.

**Offline detection (F5):** `NetworkReachabilityMonitor` is a lightweight `NWPathMonitor` wrapper as a `@MainActor` singleton, started in `AIFitnessCoachApp.init()` so it has the correct state from launch. The banner observes it via `@ObservedObject` for live re-render; the "Last sync HH:MM" text comes from `SyncStatusSnapshot.lastAnySyncSuccessAt` (max of the Strava + HK timestamps).

## 10. Workout Pattern Detection (Epic 32)

`WorkoutPatternDetector` analyses a 5s-resampled sample series (HR + power + cadence) and recognises four physiological signals per Joe Friel / TrainingPeaks thresholds:

| Pattern | What it detects |
|---|---|
| **Aerobic decoupling** | HR drift at equal power → aerobic ceiling exceeded |
| **Cardiac drift** | HR rises without a pace increase → fatigue / dehydration |
| **Cadence fade** | Cadence drops off in the late workout phase → muscle-fatigue signal |
| **Slow HR recovery** | HR drops insufficiently during a rest pause → insufficient parasympathetic recovery (see §12) |

Detection is **gated on personal HR zones** (Epic 44): cardiac drift only triggers in Z1-Z3 (Z4/Z5 drift is expected). HR recovery was rewritten in Epic #47 to pause-based detection with `referenceHR` scaling — see §12 for the details. Decoupling and cadence fade take no profile input.

`WorkoutAnalysisView` renders significant patterns as `PointMark` pins on the HR chart + a chip row + a "Coach analysis" card with a 3-sentence Gemini synthesis (cached per workout, no repeated API calls). Patterns from recent workouts (`WorkoutHistoryContextBuilder`, Epic 45) are also injected into the chat coach prompt so the coach proactively refers to them when adjusting plans.

**Coach-analysis context (Epic #48):** besides patterns and recovery events, the `WorkoutInsightService` also receives the goal and periodisation status — `BlueprintContextFormatter.format(results:)` for blueprint milestones (✅/❌ per critical workout) and `PeriodizationResult.coachingContext` for the active phase (Base/Build/Peak/Taper) + success criteria. The system instruction tells the coach to make one concrete link to the goal in every analysis ("fits your Build phase for the marathon, and this 32km approaches your 28km long-run milestone") when that context is present. The cache key contains a `goalsFingerprint` so a milestone achievement or phase transition automatically triggers a new analysis instead of serving a stale framing from the cache.

**Weather context (Epic #49 + #50 + #52):** `ActivityRecord.temperatureCelsius` and `humidityPercent` are filled via two sources:
1. **HK metadata** (Epic #49) — `HKMetadataKeyWeatherTemperature` / `HKMetadataKeyWeatherHumidity` whenever the iPhone was present during an outdoor workout. A cross-source merge in `ActivityDeduplicator` ensures Strava records inherit the HK weather via dedupe.
2. **Open-Meteo historical** (Epic #50) — for Garmin/bike-computer-only rides without iPhone presence. `HistoricalWeatherService` queries `archive-api.open-meteo.com` (data >5 days old) or `api.open-meteo.com/v1/forecast` with `past_days` (more recent) based on Strava's `start_latlng` + `startDate`. Privacy: GPS rounded to 0.1° (~11km) before the API call. Called in both Strava ingest paths (auto-sync + historical sync) as an idempotent helper — skips if the HK merge already supplied weather.

**Hourly weather range (Epic #52):** a single-point snapshot at ride start misses the variation during a long workout (a run that started at 9:43 at 15°C but peaked at 22°C). `HistoricalWeatherService.fetchWeatherRange(latitude:longitude:startDate:endDate:)` fetches all hourly buckets within `[start, end]` and aggregates, via the pure helper `extractWindowAggregates`, into peak + avg for temperature and humidity. Schema V3 → V4 (lightweight, see §6) adds `startLatitude`/`startLongitude` to `ActivityRecord`; `HistoricalWeatherService.enrichRecord` persists those on every Strava ingest so the Coach call can fetch the range afterwards without querying the Strava API again. `WorkoutAnalysisView` fetches the range before the cache check (it is part of the `weatherFingerprint`).

`WorkoutInsightService` injects the final result as a `[WEATHER DURING WORKOUT — range]` block (peak + avg) when a range is available, otherwise the `[snapshot]` block. The system instruction tells the coach to use the **peak** temperature as the lower bound for heat-stress evaluation (thresholds: >25°C or >70% humidity). The cache fingerprint contains `weatherFingerprint` (incl. the range peak) so a later sync or range update triggers a new analysis.

**Location-aware per-stage forecast (Epic #56):** the dashboard forecast (`WeatherManager`) is always at the *device* location. For a multi-day event the week schedule instead shows the forecast at the approximate location of each stage day. The route is derived **app-side** from the goal's free text — `RouteParser` (pure-Swift, NL/EN/DE/ES) extracts start/end place names from "van X naar Y"-style titles, then `CLGeocoder` resolves them to coordinates. `StageLocationInterpolator` (pure-Swift, great-circle slerp) places each stage between start and end (day 1 = start, day N = end). `StageWeatherService` (`@MainActor` `ObservableObject`) orchestrates: resolve route (cached in UserDefaults, keyed by the goal id + its `routeSourceText` so a title edit recomputes it), interpolate, fetch each stage location's forecast via the reusable `OpenMeteoForecastClient` (which owns the WMO→Dutch mapping `WeatherManager` now delegates to), and reverse-geocode an "≈ <place>" label. Bounded by a 16-day forecast horizon + a per-session throttle. No schema migration — route data is derived/re-computable, so it lives in a UserDefaults cache, not SwiftData. `StageDayRowView` renders the stage forecast + place label, falling back to the home forecast when no route is found. Per-stage weather is **UI-only** for now (not injected into the coach prompt).

---

## 11. CI Pipeline (Epic 46)

GitHub Actions runs two workflows on every push to `main` and every PR:

### `iOS CI` — 4-job DAG

```
┌─ SwiftLint        (parallel, no needs)
├─ Unit Tests ──────┬─ UI Tests
└──────────────────┴─ Coverage Report
```

- **`SwiftLint`** — `swiftlint --strict` on the `.swiftlint.yml` config. 938→0 violations baseline; 1 new violation breaks CI.
- **`Unit Tests`** — `xcodebuild test -only-testing:AIFitnessCoachTests -enableCodeCoverage YES`. xcresult as an artifact (7d).
- **`UI Tests`** — `-only-testing:AIFitnessCoachUITests -parallel-testing-enabled NO`. Sequential to avoid xctrunner-clone flakiness (Epic 46.4 root cause). xcresult + CoreSimulator logs as artifacts (14d).
- **`Coverage Report`** — `needs: [unit-tests, ui-tests]`. `scripts/coverage-report.py` merges both xcresults per-file (max-coverage approximation) and generates per-directory markdown with aggregates (Testable / Views / Total).

### `CodeQL Security Analysis`

A matrix with two languages, each on the right runner:
- **Swift** on `macos-latest` with a manual `xcodebuild clean build`.
- **Actions** on `ubuntu-latest` (10× cheaper) — pure YAML static analysis on workflow files.

### Concurrency

Both workflows have `concurrency: ${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true` — force-pushes on a PR branch cancel older in-flight runs. Saves runner minutes and prevents rollup confusion.

---

## 12. HR recovery via pause detection (Epic #47)

HR recovery is only physiologically interpretable when the external load drops away — a vagal-tone measurement against a continuous effort is not recovery, but an arbitrary spike-to-spike comparison. The Epic 32 implementation made that mistake: global peak + measure HR exactly 60s later. On continuous rides the user was pedalling again 60s after the peak, so a visual dip of 40 BPM during a short stop came out of the detector as a "4 BPM drop".

### `Services/PauseDetector.swift`

Pure-Swift, AppStorage-free, no framework deps. Detects contiguous samples where both `power < 5` and `cadence < 5` (nil values count as "no signal", not "active") for at least `minimumPauseSeconds = 45`. Pre-check: the workout must have at least 10 samples with actual activity — prevents a sport without both sensors (swimming) from being seen as one long pause.

Per detected pause it yields a `PauseRecoveryEvent` with:
- `pauseRange`: the full time span of the pause
- `peakHRInPause`: the highest HR within the pause — anchor point for the measurement
- `measurementWindow`: 90s from the `peakHRInPause` timestamp, clamped to the pause end
- `minHRInWindow`: the lowest HR seen in that window
- `drop = peakHRInPause − minHRInWindow`

**Why peak-anchored, not pause-start-anchored?** On an abrupt stop the HR often still peaks 5-15 seconds before it starts to drop (post-stop adrenaline / sympathetic response to the transition). If you measure from the first pause sample you capture the plateau phase, not the drop — a 40 BPM visual dip is then reported as "4 BPM". Measuring from the peak yields the physiological HRR we actually want to report.

**Why 90s, not the classic 60s?** The vagal-dominant HRR phase runs up to ~90s after the stop. In fit athletes and real-world cool-downs the drop often only gets going in seconds 10-30. 60s would underestimate the drop for Mark-like profiles; 90s captures it correctly without the measurement landing in the slow sympathetic phase.

### `WorkoutPatternDetector.detectHeartRateRecovery` — pause iteration

Iterates the `PauseDetector.detect(in:)` output, computes `ratio = drop / referenceHR` per event, and pins the pause with the lowest ratio (worst recovery — Management by Exception §1: only show exceptions, and then the weakest signal).

**Pin consideration is separate from detection.** PauseDetector finds pauses ≥45s for the coach-prompt context, but for pin consideration the pattern detector filters on `hrRecoveryMinPauseForPinSeconds = 90`. Reason: a traffic-light/junction stop of 45-89s is physiologically not a "recovery event to inform the user about". Before this bound, a short stop with a small drop (4-8 BPM in 60s) regularly won the pin over a long coffee stop with excellent recovery — the worst-ratio strategy picks the wrong signal if short stops are allowed to participate at all.

Thresholds relative to `referenceHR`:
- `≥ 0.15` ratio → excellent, no pin
- `0.12 – 0.15` → mild
- `0.09 – 0.12` → moderate
- `< 0.09` → significant

`referenceHR` cascade: `lactateThresholdHR` (preferred, the most physiologically correct anchor) → `0.88 × maxHeartRate` (common LTHR/HRmax relationship) → `referenceHRFallback = 165` (population default that reproduces the old absolute thresholds: 165 × 0.15 ≈ 25 BPM good bound).

### Coach prompt — `WorkoutInsightService.RecoveryEventSummary`

Besides the pin, the coach receives via `WorkoutInsightService.InsightContext.recoveryEvents` **all** detected pause events — including the excellent ones. The service's system instruction tells the AI how to handle them: an excellent recovery may be framed positively ("your autonomic nervous system responded strongly") when relevant to the patterns, a mediocre/poor event reinforces fatigue suspicions from other patterns. Workouts without a pause (interval tests, tempo loops) yield no events and the coach does not mention it — no measurement window = no topic.

### Tradeoff vs. cardiac drift

Workouts without a pause no longer get an HR-recovery signal. That is correct behaviour, but it means the `cardiacDrift` detector (HR rise between half 1 and 2 at equal intensity) is now the only HR-only fatigue layer for continuous rides. That is deliberate: drift works on the actual physiological signal of Z1-Z3 aerobic work and is meaningful on continuous effort, while recovery can only be measured physiologically correctly during rest windows.

## 13. Localization & multilingual coach (Epic #37)

The app UI and the AI coach are multilingual — **NL, EN, DE, ES**. The codebase, code comments and the coach prompt are English; only translations and the coach's *output language* vary.

### Language preference — `AppLanguage`

`Localization/AppLanguage.swift` is the single source of truth. It resolves the active `Locale` for two readers that can't share state:
- **SwiftUI views** get it via `.environment(\.locale, …)` injected at the app root.
- **Pure-Swift services / prompt builders** read `AppLanguage.currentLocale` / `AppLanguage.currentPromptLanguageName`, backed by the same `@AppStorage` key (`vibecoach_appLanguage`).

Default is `.system` (follow the device). Picking a specific language writes an `AppleLanguages` override (`applyToBundleOverride`) so the bundle loads the matching `.lproj` on the next launch — hence the Settings picker shows a relaunch note (iOS reads `AppleLanguages` once at launch; `.environment(\.locale, …)` only steers date/number formatting, not String-Catalog lookup).

### UI strings — `Localizable.xcstrings`

A single String Catalog (source language `nl`, columns en/de/es, ~527 keys). Two render patterns, because `Text("literal")` and `Text("literal \(interp)")` localize automatically but `Text(stringVariable)` renders **verbatim**:
- **Shared row/card components** with a `String` parameter → render via `Text(LocalizedStringKey(param))` (one fix localizes all call sites; brand names fall back to themselves).
- **Computed `-> String` UI props** → wrap returns in `String(localized:)`.
- **Numeric interpolation in a format key**: pre-format the number into a `String` and interpolate as `%@`, so the generated catalog key avoids `%lld`-vs-`%@` mismatches that silently fall back to the source language.

`xcodebuild` does not write extracted keys back to the catalog (only an Xcode IDE build does); keys for the runtime-key patterns above are hand-authored and verified via the compiled `.lproj`.

### Multilingual coach — `respond in {language}`

The system instruction is **English** for maintainability; a single locale-dependent directive (`AppLanguage.currentPromptLanguageName`, e.g. "German") steers the output language. We do **not** maintain per-language prompt copies — the generated prose (and `motivation`/`description`/`reasoning`/`activityType` JSON fields) come back in the user's language, the English instruction body stays fixed. `ChatViewModel.systemInstruction`, `ChatScopeInstruction.text` and `WorkoutInsightService.systemInstruction` are computed so the language is read at call time.

### UI-vs-prompt split

Enum display values that are **interpolated into the coach prompt** (`SportCategory`/`SessionType.displayName`, `BodyArea.rawValue`/`severityLabel`, `GoalBlueprint.displayName`) deliberately stay Dutch as the prompt term, while the **View render sites** localize them via `LocalizedStringKey(value)`. This keeps the prompt structurally stable while the UI shows the translated term. Structural prompt markers (`[CURRENT COMPLAINTS]`, `🚨 CRITICAL MILESTONE SHORTFALL`, …) must match between every emitter (formatters/services) and the `systemInstruction` reference — a rename in one place without the other breaks the coach's section lookup.

### Language-independent detection

Free-text and coach-output classification can't assume Dutch: `BodyArea.injuryKeywords` (NL+EN+DE+ES union), `SuggestedWorkout.resolvedDate` (day-name parsing incl. localized formats like "Sonntag, 7. Juni" — punctuation-stripped), and `SuggestedWorkout.isRestDay`/`.kind` (rest + sport classification via multilingual keywords + the duration signal) all work across the supported languages.

### Tests

The app is now locale-sensitive, so UI tests run forced in Dutch (`-testLanguage nl`). Unit tests that assert localized user-facing output compare against `String(localized:)` of the same key (locale-agnostic) rather than a hardcoded translation.
