# VibeCoach Roadmap — Archive (completed epics)

Full history of completed epics (✅). The **live** plan — open & active work + the "Open work" index — is in **[ROADMAP.md](ROADMAP.md)**. This file grows append-only and is read on demand only.

Legend: ✅ done · 🔄 active · ⏳ backlog

---

### ✅ Phases 1–9: Foundation & Intelligent Coach

| Phase | What was built |
|------|-------------------|
| **1–5** | iOS app (SwiftUI) & SwiftData, OAuth2 Strava, Node.js webhook backend with APNs (later replaced by Engine A — see Epic 13), deep-linking on `activityId` |
| **6** | Historical sync, context injection & proactive overtraining warnings |
| **7** | Apple HealthKit integration — Banister TRIMP calculation (HRR, Cardiac Drift, Training Load) locally on device |
| **8** | Interactive 7-day training calendar; Readiness Calculator injects cumulative TRIMP + active goals into the prompt |
| **9** | Smart Expiring Memory (temporary injuries get an expiry date), workout actions (Skip / Alternative), Performance Baseline (average pace injected into AI prompts) |
| **10** | Open Source release — secrets removed, documentation tidied up |
| **11** | Coach UX refactor: `TrainingPlanManager` as Single Source of Truth, central TabBar Coach button |
| **12** | Multi-Goal Burndown Chart (Swift Charts, scrollable), TRIMP Explainer card, hybrid Forecast line (planned schedule + historical burn rate) |

---

### ✅ Epic 13: Proactive Coach & Background Sync

**Dual Engine Architecture** that wakes the app without the user having to do anything. See [ARCHITECTURE.md](ARCHITECTURE.md) for the technical explanation.

* **Engine A (Action Trigger):** `HKObserverQuery` + `enableBackgroundDelivery`.
* **Engine B (Inaction Trigger):** `BGAppRefreshTask` via `BGTaskScheduler`.
* **Recovery Mode:** `requestRecoveryPlan()` automatically builds a detailed prompt and instructs the AI to produce a 7-day adjusted schedule.
* **Physiological Guardrails:** Hard limits in the AI prompt — 10–15% progression rule, Base Building when >8 weeks remaining, max 60 minutes for indoor sessions.

---

### ✅ Epic 14: The Vibe Score — Readiness

**HealthKit meets AI:** a daily body battery (0–100) that steers the coach.

* `heartRateVariabilitySDNN` (HRV) and `sleepAnalysis` via HealthKit — fully local, privacy-first.
* `ReadinessCalculator` combines Sleep (50%, linear 5–8h) + HRV (50%, current vs. 7-day personal baseline) into a score of 0–100.
* `VibeScoreCardView` (green ≥80, orange 50–79, red <50) at the top of the dashboard.
* The Vibe Score is cached in `AppStorage` and injected into *every* AI prompt. Hard system instruction: the AI may never contradict the score.

---

### ✅ Epic 16: Dynamic Periodisation & Macrocycles

The app thinks in training phases — no longer a linear burndown.

* `TrainingPhase` enum (`.baseBuilding`, `.buildPhase`, `.peakPhase`, `.tapering`), determined automatically from weeks remaining.
* The weekly TRIMP target scales along — ×1.00 (Base), ×1.15 (Build), ×1.30 (Peak), ×0.60 (Taper). Tapering-overload detection triggers a separate red warning.
* The coach receives a `[PERIODISERING]` block per goal with phase-specific restrictions and the concrete mathematically-adjusted TRIMP target.

---

### ✅ Epic 17: Goal-Specific Blueprints

Hardcoded sports-science rules per discipline.

* `GoalBlueprint` struct with `minLongRunDistance`, `taperPeriodWeeks`, `weeklyTrimpTarget`, `essentialWorkouts`. Hardcoded Marathon (28+32 km), Half Marathon (16+18 km), Cycling Tour (60+100 km).
* `BlueprintChecker` detects the blueprint type via keywords or a SportCategory fallback.
* Blueprint milestones + periodization context injected into all AI prompts.
* `PhaseBadgeView` above the schedule, `MilestoneProgressCard` with progress bars per goal.

---

### ✅ Epic 18: Subjective Feedback — RPE & Mood

How hard did the training feel? — independent of what the heart-rate monitor says.

* **Post-Workout Check-in:** `PostWorkoutCheckinCard` appears on the dashboard after a real training (≤48h, ≥15 min, TRIMP ≥15). RPE slider (1–10) + five mood buttons.
* Commute rides and short walks are skipped automatically.
* The AI receives a `[SUBJECTIEVE FEEDBACK]` block in every prompt. Low TRIMP + RPE ≥8 = an early warning signal for overtraining.

---

### ✅ Epic 19: Tech Debt, MVVM Refactor & UI Testing

Extensive cleanup. Code coverage rose to 62%.

* **Magic Numbers → Constants:** `WorkoutCheckinConfig` enum centralises the RPE thresholds.
* **Accessibility Identifiers:** Core components marked for robust UI testability.
* **UI test suite:** 8 XCUITests for TabBar, Dashboard, navigation and the RPE check-in. HealthKit and notification popups bypassed via `-isRunningUITests`.
* **Unit Tests:** `ReadinessCalculatorTests` (8 tests) + `TrainingPhaseTests` (11 tests).

---

### ✅ Epic 20: App Store Ready — Onboarding & Polish

* **Sprint 20.1 — BYOK & Multi-Provider:** `AIProvider` enum (Gemini / OpenAI / Anthropic). `AIProviderSettingsView` in Settings. `NoAPIKeyView` empty state in the Coach tab when no key is set.
* **Sprint 20.2 — Onboarding Flow:** 4-page `TabView` carousel with an inline BYOK entry card. Permissions only via buttons, never automatically.
* **Sprint 20.3 — Splash Screen & App Icon:** Native splash via `UILaunchScreen` in `Info.plist`. Onboarding secured: no permission request outside explicit buttons.

---

### ✅ Epic 14b: Injury-Impact Intelligence & Vibe Score Stability

* **14b.1 — Injury-Impact Matrix:** A penalty multiplier (1.0–1.4×) raises the effective TRIMP for risky sport pairings.
* **14b.2 — ACWR Banner Logic:** Dashboard banner based on the Acute:Chronic Workload Ratio (threshold 1.5×). States: `overreached`, `lowVibeHighLoad`, `behindOnPlan`.
* **14b.3 — Chat UX & Retry:** Improved prompt suggestions, a `Retry` button on AI errors.
* **14b.4 — Vibe Score Auto-Calculation:** `DashboardView` calculates the Vibe Score automatically on `onAppear`. 5s time-out via `withTaskGroup`. HRV window enlarged to 48h.

---

### ✅ Epic 21: External Factors — Weather & Sleep

* **21.1 — Open-Meteo Weather Forecast:** `WeatherManager` fetches the 7-day weather forecast. The coach swaps trainings on ⚠️ BAD OUTDOOR WEATHER. Wind >30 km/h triggers a cycling suggestion towards a calmer day. `WeatherBadgeView` on every `WorkoutCardView`.
* **21.2 — Sleep Stages:** `fetchSleepStages()` fetches `.asleepDeep`, `.asleepREM`, `.asleepCore`. Penalty points for <15% deep sleep. `SleepStagesBarView` in the Vibe Score card.

---

### ✅ Epic 23: Blueprint Analysis & Future Projections

* **23.1 — Target Gap Analysis:** `ProgressService` calculates the gap between the linearly-expected and the actually-achieved volume. `GapAnalysisCardView` shows a progress bar per TRIMP and km.
* **23.2 — Future Projection Engine:** `FutureProjectionService` extrapolates a 3-week sliding-window trend line. `ProjectionStatus`: `alreadyPeaking / onTrack / atRisk / unreachable`.
* **23.3 — Visual Progress Hub:** `BlueprintTimelineView` with Ideal / Actual / Forecast lines. `GoalDetailContainer` bundles everything per goal.

---

### ✅ Epic 24: Nutrition & Fueling Engine

* **24.1 — Physiological Profile:** `UserProfileService` fetches weight, height, age and sex via HealthKit with fallbacks. `NutritionService` calculates BMR (Mifflin-St Jeor) and carb/fluid needs per zone.
* **24.2 — Two-Way Sync:** `PhysicalProfileSection` in Settings — age/sex read-only, weight/height editable. Source badge per value (❤️ HealthKit / 📱 Local / ⚠️ Default).
* **24.3 — Nutrition UI:** `WorkoutStatsRow` fueling chips (⏱/⚡/💧/🍌). `WorkoutFuelingSectionView` with per-15-min timing advice.

---

### ✅ Epic 26: UI Test Suite Fixes & ProgressService Unit Tests

* 8 UI tests run stably in CI after race-condition fixes.
* `ProgressServiceTests` full happy-path coverage.
* Coverage: 54% → **62%**.

---

### ✅ Epic 27: Improve Test Coverage

* `FutureProjectionService` tests (trend-line algorithm, safety limit, `ProjectionStatus` variants).
* `UserProfileService` tests (HealthKit fallback chain, Mifflin-St Jeor BMR).
* Coverage end result: **63%** (target ≥75% not reached).

---

### ✅ Epic #28: Goal Intent, Multi-Day Events & Stretch Goals

* `EventFormat` (`.singleDayRace`, `.multiDayStage`), `PrimaryIntent` (`.completion` / `.peakPerformance`), optional `StretchGoal`.
* `PeriodizationEngine` plans back-to-back endurance trainings for multi-day tours.
* The AI prompt always prioritises the finish line over the target time once the athlete is fatigued.

---

### ✅ Epic #29: Visual Overhaul — 'Serene' Theme

* **29.1 — Theme Engine:** `ThemeManager` + `Theme` enum (Moss, Stone, Mist, Clay, Sakura, Ink). Persistent via `UserDefaults`.
* **29.2 — Design System:** Adaptive `UIColor { traits in }` closures. `SereneIconStyle` for hierarchical SF Symbols.
* **29.3 — Settings & UI Injection:** `ThemePicker` with live preview. Dynamic tab icons via `ThemeManager.icon(for:)`.
* **29.4 — Global Theme Injection:** All hardcoded `Color.blue` and `Color.accentColor` replaced by `themeManager.primaryAccentColor`.

---

### ✅ Epic #30: V2.0 Card-Based UX Overhaul

* **30.1 — Dashboard V2:** Floating card layout. `DashboardHeaderView`, `VibeScoreCardV2`, `WeekTimelineView`, `TrendWidgetView`, `DashboardBannerView`. Build number via CI (`agvtool`).
* **30.2 — Interactive Coach Chat:** `CoachV2HeaderView`, `CoachTextCard`, `CoachInsightCard`, `PlanAdjustmentCard`. Tab icons to an outlined style.
* **30.3 — Goals V2:** `List` → card-based `ScrollView`. Progress bars per training phase per goal card.
* **Bugfixes (PR #169):** `ColorColor` typo, `TimeInterval` math → `Calendar.dateComponents`, `recoveryReason` on `AthleticProfile`, UI test suite fully updated for V2.0.

---

### ✅ Epic #31: V2.0 Onboarding Experience

A five-screen flow in the Serene/Moss style. Each screen shows a 'live preview' (Vibe Score ring, TRIMP bars, coach notification) before permissions are granted.

* **31.1 — State & Navigation:** `@AppStorage("hasCompletedOnboarding")` as the gatekeeper. `OnboardingTemplateView` as wrapper; `OnboardingView` as `TabView(selection:)`.
* **31.2 — HealthKit & Engine A:** `HealthKitManager.shared.requestOnboardingPermissions()`. After the grant, `ProactiveNotificationService.shared.setupEngineA()` starts.
* **31.3 — Style Foundation:** Card style aligned with the Dashboard (`cornerRadius 16`, soft `shadow`).
* **31.4 — Persistence:** `UserConfiguration` (SwiftData `@Model`) for `onboardingDate`. API keys via `KeychainService` — never `UserDefaults`.
* **31.6 — Prototype Alignment:** 5-step flow matching the prototype. Goal-selection screen removed. Continuous progress bar + "X / N" counter. The system default color scheme is explicitly respected.

---

### ✅ Epic #34: V2.0 Fit & Finish — UI Polish & Tech Debt

* **34.1 — Safe Area:** `scrollEdgeMaterial(isActive:)` modifier for a scroll-aware `regularMaterial` strip below the status bar.
* **34.2 — Dynamic Build & Version Number:** From `Bundle.main.infoDictionary` in `SettingsView`.
* **34.3 — Smart Insights, Haptics & Empty States:** Dynamic `CoachInsightCard` observations. `.impact(.medium)` feedback via the `Haptics` helper. Empty lists → `ContentUnavailableView`.
* **34.4 — UI Consistent Spacing:** `lineLimit` + `minimumScaleFactor` for the iPhone SE.
* **34.5 — Hardcoded Data Cleanup:** SHORT/WHAT-I-SEE cards fully data-driven via `@Query`. Dummy toggles removed from Settings.

---

### ✅ Epic #57: Simplify the RPE check-in — one-tap effort + feel

The post-workout check-in (`PostWorkoutCheckinCard` in `DashboardView.swift`) used to ask for an **RPE slider 1–10** (anchors "Very light"/"Maximal") plus a **separate mood row** (Calm/Good/Strong/Pain/Exhausted) and a standalone "Save" button. Problem (user feedback June 2026): a bare number between 1 and 10 is unclear — you have to guess what a "6" means — and the two separate questions + save button make a quick check-in cumbersome. Downstream, `LastWorkoutContextFormatter` already reduces the RPE to four categories anyway (light 1–3 / moderate 4–6 / hard 7–8 / maximal 9–10), so the fine-grained scale adds little for the coach.

**Agreed design (June 2026):** replace slider + separate mood with **one row of holistic choice buttons** (talk-test as anchor), one tap = done. Each button maps under the hood to an `(rpe: Int, mood: String)` pair, so `ActivityRecord` (`rpe: Int?` + `mood: String?`) stays unchanged → **no schema migration** (§2.1) and **no coach-prompt change** (the overtraining-discrepancy check, `LastWorkoutContextFormatter` and `SessionType.expectedRPERange` keep working on the stored number). The "Pain / complaint" choice remains its own option because that is the most important injury/safety signal for the coach. The "Ignore" button (sentinel `rpe = 0`) stays.

The five options + under-the-hood mapping:

| Button | Description (talk-test) | rpe | mood |
|---|---|---|---|
| 🟢 Easy | "Could chat easily" | 2 | Good |
| 🟡 Solid effort | "Firm, but felt good" | 5 | Strong |
| 🟠 Hard | "Really suffered, could barely talk" | 8 | Exhausted |
| 🔴 Empty / spent | "Couldn't go on" | 9 | Exhausted |
| 🩹 Pain / complaint | "Something hurt" | 5 | Pain |

* **✅ Story 57.1 — UI redesign of `PostWorkoutCheckinCard`.** Slider + separate mood row + standalone "Save" button removed; instead one vertical list of five holistic options (icon + label + talk-test description, colour by level). One tap → `saveFeedback(_:)` sets `activity.rpe`/`activity.mood` and calls `onSaved` directly; the card disappears once `recentUncheckedActivity` becomes nil. The new value type `WorkoutCheckinOption` (`DashboardView.swift`, AppStorage-free, §6) is the single source of truth for the mapping. The "Ignore" path (sentinel `rpe = 0`) is unchanged. Accessibility: `RPESlider`/`RPEOpslaanButton` are dropped, with a `RPEOption_<id>` identifier per option (easy/good/hard/empty/pain). UI tests (`AIFitnessCoachUITests` + `OnboardingE2ETests`) converted to the new identifiers.
* **✅ Story 57.2 — i18n.** Nine new label + description strings in `Localizable.xcstrings` (NL/EN/DE/ES); "Hard" already existed and is reused (unique JSON key). Outdated keys ("Effort (RPE)", "Very light", "Maximal", separate mood labels) remain as harmless `stale` entries instead of being hand-removed from the 11k-line file — Xcode marks unused keys as stale automatically.
* **✅ Story 57.3 — Readable mood in the coach prompt.** The mood is stored on `ActivityRecord` as an SF Symbol name (e.g. "bandage.fill"); the coach saw it raw ("Mood: bandage.fill"). `LastWorkoutContextFormatter.readableMood(_:)` (pure-Swift, §6) now maps it to a readable English word (good/strong/exhausted/in pain/calm) — prompt language is English (§13). Unknown/legacy values (old emoji moods) pass through unchanged so no historical data is lost. 2 unit tests added in `LastWorkoutContextFormatterTests`.

**Merged via PR #312. Effort:** ~2–4h. **Out of scope:** data-model extension (extra feel axis), writing back to HealthKit, migrating historical check-ins. **Open point:** the final emoji/labels may still shift after on-device review.

---

### ✅ Epic #56: Location-aware weather forecast for multi-day routes

The weather on the dashboard always came from the **device location** (home). For a multi-day tour (e.g. "Cycle from Arnhem to Karlsruhe in 5 days") you want a **reasonable estimate** per stage day of the weather where you roughly are then — not home. The route is derived automatically from the goal title/notes; per stage we interpolate the location along the route. No GPS precision, but "roughly where am I that day".

**Agreed (June 2026):** route extraction **automatic from title/subtext** (LLM-free: heuristic parser + `CLGeocoder`); per-stage weather **in the UI only at first** (coach-prompt injection as a possible later story). No schema migration — route + place names are cached app-side (UserDefaults, title as invalidation).

* **✅ Story 56.1 — Route extraction + geocoding.** `RouteParser` (pure-Swift, NL/EN/DE/ES): pulls start/end place names from "from X to Y"-style titles (two-pass to dodge the greedy ES connector "a"). `CLGeocoder` → coordinates. `EventRoute`/`GeoCoordinate` value types; `FitnessGoal.routeSourceText` as source + cache key. 13 unit tests in `RouteParserTests`.
* **✅ Story 56.2 — Per-stage interpolation + weather.** `StageLocationInterpolator` (pure-Swift, great-circle slerp: day 1 = start, day N = end). `OpenMeteoForecastClient` (reusable Open-Meteo fetch on arbitrary coordinates; WMO mapping centralised, `WeatherManager` delegates). `StageWeatherService` (`@MainActor` `ObservableObject`): resolve route (cached) → interpolate per stage → fetch forecast → reverse-geocode place name (cached), with a 16-day horizon + session throttle. 7 unit tests in `StageLocationInterpolatorTests`.
* **✅ Story 56.3 — UI.** `StageDayRowView` shows the stage-location forecast + "≈ <place>" label (falls back to home weather if there is no route). `WeekTimelineView` gets `stageWeather: [Date: StageWeather]`; `DashboardView` holds the `StageWeatherService` and refreshes on appear.

**Merged via PR #311. Effort:** ~6–10h. **Out of scope (possible follow-up stories):** stage weather in the coach prompt; explicit route fields in the goal editor; per-stage distances.

---

### ✅ Epic #55: Multi-day events first-class

A multi-day goal (e.g. "Cycle from Arnhem to Karlsruhe in 5 days") is now modelled with a single `targetDate`. Consequence: the event days are unknown to the planner, the schedule just plans through them (strength training, other-goal sessions), and the "5 consecutive tour days" are nowhere visible. Moreover the coach races the event because `resolvedFormat`/`resolvedIntent` fall back to `singleDayRace`/`peakPerformance` when those fields are not set explicitly.

**Agreed behaviour (June 2026):** `targetDate` = **start day**; event = `targetDate … +N-1`. Tour days show as **stage entries** ("Stage X/N") in the week schedule; **no** other training or fixed preferences in that window (cross-goal suppression). The coach treats it as a tour, not a race.

* **✅ Story 55.1 — Data model + migration + input (PR #307, merged on `main`).** `FitnessGoal.eventDurationDays: Int?` (1 = single-day). Computed `resolvedEventDurationDays`/`eventEndDate`/`isEventDay(_:)`/`eventStageIndex(for:)`. SchemaV4→V5 (lightweight, pure addition) + container bump in `AIFitnessCoachApp.makeModelContainer()` to `SchemaV5.models` + a file-backed migration test (§2.1). AddGoal/EditGoal: a "Number of days" stepper + a conditional "Start date" header when format = Multi-Day Stage.
* **✅ Story 55.2 — Stage entries in the week schedule (PR #308, merged on `main`).** Event days that fall in the shown week render as "Stage X/N" + the event title (checkered-flag icon, accent colour), instead of coach trainings. Synthesised app-side via the new pure helper `Services/WeekScheduleBuilder` (AppStorage-free, §6): a `WeekDayEntry` per weekday (`.workout` or `.stage`), with stages taking precedence over coach trainings on event days (visual cross-goal suppression). Only multi-day events count (`resolvedEventDurationDays > 1`); a single-day race keeps normal workout/rest rendering. `WeekTimelineView` gets an `eventGoals` param + a new `StageDayRowView` + stage marking in `DayCircleView`; `DashboardView` passes `goals` through. 7 unit tests in `WeekScheduleBuilderTests` (synthesis, precedence over workout, single-day exclusion, window overlap with the global stage index, completed event, overlapping events). The hooks `goal.isEventDay(_:)` + `goal.eventStageIndex(for:)` from 55.1 are reused.
* **✅ Story 55.3 — Prompt event window + suppression (PR #309, merged on `main`).** A new pure helper `ViewModels/EventWindowContextFormatter` injects an `[EVENT WINDOW — '<title>': <ISO start> … <ISO end>]` block per multi-day event into the coach prompt: (1) plan NO other training on the event days (no strength/gym, no sessions for other goals), (2) ignore fixed preferences within the window, (3) cross-goal suppression (other-goal base yields), (4) after the event, first plan recovery (1–3 calm days, scales with event length). Cached via `ChatViewModel.cacheEventWindow(_:)` (AppStorage), injected in `buildContextPrefix` after `[GOAL INTENTS AND APPROACH]`; `DashboardView` fills the cache. **"Races-the-event" bug fixed:** `FitnessGoal.resolvedFormat`/`resolvedIntent` now always treat a goal with `eventDurationDays > 1` as `.multiDayStage` / (for nil intent) `.completion`, regardless of a missing `format`. 15 unit tests in `EventWindowContextFormatterTests`. **Expected behaviour:** an already-generated schedule only changes on a replan — the prompt rules apply to new/recalculated schedules.
* **✅ Story 55.4 — EditGoalView multi-day correctness (PR #310, merged on `main`).** On-device follow-up: (1) for a Multi-Day Stage the date field is now called "Start date" (matching AddGoalView) instead of the confusing "Target date"; (2) a goal with `format == .multiDayStage` but a nil/<2 day counter (pre-#55 or a format switch without the stepper) was silently NOT recognised as multi-day — the format picker now sets a default of 5 and `onAppear` backfills an existing goal. AddGoalView already guaranteed this for new goals.

**Merged (PR #307/#308/#309/#310). Effort:** ~10–16h.

> **Tech note (SwiftData pitfall, kept as a lesson):** the 55.1 CI blocker was a crash `SwiftData/ModelContext.swift:712: Failed to cast model AIFitnessCoach.FitnessGoal … to FitnessGoal`. Not the new V4→V5 test, but `SchemaMigrationV2ToV3Tests`/`…V3ToV4Tests` still did their `FitnessGoal` `insert`/`fetch` with the **live** class, while `FitnessGoal` (like `ActivityRecord` since Epic #52) has had a nested snapshot `SchemaV4.FitnessGoal` since Epic #55. The V2/V3/V4 schemas register the entity via that snapshot → fetch+cast to the live class crashes (process-global entity-class binding; only visible in combination with other classes). **Fix:** in those migration tests, `insert`/`fetch` on the snapshot type, exactly the existing ActivityRecord precedent (§2.1). Pure test code.

---

### ✅ Epic #32: Deep-Dive Physiological Analysis

From averages to granular physiological patterns. The coach reads the full story from the raw time-series data.

* **✅ Story 32.1 — Time-Series Data Pipeline (PR #200, #201):** `WorkoutSample` `@Model` (Route A: `workoutUUID` foreign key to `HKWorkout`, no redundant Workout cache), `SampleResampler` with three strategies (average for HR/Power/Cadence, linear interpolation for Speed, delta-accumulation for Distance) and a `@ModelActor` store that idempotently replaces samples per workout. HK fetch via `HKQuantitySeriesSampleQuery` over all parent samples. `DeepSyncService` fetches all workouts from the past 30 days once and runs them through the ingest pipeline — idempotency via `processedWorkoutUUIDs` (UserDefaults JSON set), the `hasCompletedInitialDeepSync` flag only turns `true` once ALL workouts in the window are processed. Unit tests in `SampleResamplerTests` + `DeepSyncServiceTests`.
* **✅ Story 32.2 — Annotated Charts UI (PR #202, #204, #205):** `WorkoutAnalysisView` with stacked Swift Charts (HR `LineMark` on top, speed/power `AreaMark` below) and a shared scrubber overlay that follows both axes in sync. A floating header shows time · BPM · m/s or W under the scrubber position. Entry point: `RecentWorkoutsSection` on the Dashboard below TrendWidget — only HealthKit records (UUID-parseable `id`) are clickable. Strava records are shown as a static context row. Empty state ("Deep Sync is running in the background") when the `WorkoutSample` set is empty. Pure-Swift helpers (`WorkoutAnalysisHelpers`) for nearest-sample lookup and secondary-series choice, with 8 unit tests. **Annotation pins on the chart deliberately split off to 32.3b** once the AI-prompt format is fixed.
* **✅ Story 32.3a — Pure-Swift pattern detectors:** `WorkoutPatternDetector` (pure-Swift, AppStorage-free) with detectors for the four physiological phenomena: **aerobic decoupling** (HR drift relative to power or pace; Pa:HR thresholds 3 / 5 / 8% mild/moderate/significant), **cardiac drift** (HR-only drift between half 1 and half 2 in aerobic workouts), **cadence fade** (cadence drop between the first and last quarter, with a zero-cadence filter so stops give no false signal), and **HR recovery** (BPM drop in the 60s after the global peak effort). They return `WorkoutPattern` value types with `Severity`, `ClosedRange<Date>` and a human-readable detail string. 22 unit tests in `WorkoutPatternDetectorTests` cover threshold edges, skip paths, plateau edge cases and `detectAll` aggregation.
* **✅ Story 32.3b — Annotation pins + Coach-analysis card:** Patterns from 32.3a render as `PointMark` annotations on the HR chart in `WorkoutAnalysisView`, coloured by severity (mild/moderate/significant → green/orange/red). Directly above the chart: a chip row that shows each pattern `kind` + numeric value, and a "Coach analysis" card that generates a 3-sentence synthesis of the patterns via `WorkoutInsightService` (Gemini) ("decoupling + cardiac drift = aerobic ceiling exceeded, may be due to heat — was that deliberate threshold work?"). `WorkoutInsightCache` keeps the narrative per `activityID + pattern fingerprint` so reopening the same workout costs no API call; on re-classification the cache invalidates automatically. `WorkoutPatternFormatter` (pure-Swift) serialises the patterns into prompt snippets and builds the fingerprint. 22 unit tests cover formatter + cache.
* **✅ Story 32.3c — AI context injection in the chat coach:** `ChatViewModel.workoutPatternsContext` (`@AppStorage`) is filled by `DashboardView.refreshWorkoutPatternsContext()` with significant patterns from the past 7 days, and `buildContextPrefix` injects them into every chat prompt under a new `[FYSIOLOGISCHE PATRONEN IN RECENTE WORKOUTS:]` block with explicit behaviour rules (only respond when the user reflects, drift+decoupling trigger a targeted question, slow HR recovery linked to TRIMP/VibeScore for recovery advice). Mild patterns are filtered out so the prompt stays calm.

---

### ✅ Epic #33: Advanced Session Architecture

Trainings are sessions with an explicit physiological intent. Completed April 2026 — the user validated the whole flow on-device: session types are auto-classified and manually overridable, swaps are sacred in every prompt, and the coach calibrates its tone on intent vs. execution.

* **✅ Story 33.1 — Session-Type Taxonomy:** Split into two PRs due to scope.
  - **✅ 33.1a — Domain & classifier:** `SessionType` enum (7 cases: `vo2Max`, `threshold`, `tempo`, `endurance`, `recovery`, `social`, `race`), `SessionIntent` struct with zone range + expected RPE + coachingSummary per type, `sessionType` as an optional property on `ActivityRecord` (lightweight migration), and `SessionClassifier` with three strategies (keywords, zone distribution via `WorkoutSample`, average-HR fallback). 20 unit tests in `SessionClassifierTests`.
  - **✅ 33.1b — UI override + auto-classifier + AI context injection:** `HeartRateZones` helper for maxHR via the Tanaka formula (208 - 0.7×age) with a 190 fallback. `HealthKitSyncService` runs the classifier on every new `ActivityRecord` based on avg HR + duration (manual override protected — the classifier never overwrites a manually-chosen type). `WorkoutAnalysisView` gets a Menu override (SF Symbols + capsule, Serene style) that saves straight into SwiftData. `LastWorkoutContextFormatter` (testable) builds the last-workout block in the prompt and adds `sessionType.displayName` + `intent.coachingSummary` — the coach gets textual intent ("Active recovery" instead of just "recovery"). 8 unit tests in `LastWorkoutContextFormatterTests` + 7 in `HeartRateZonesTests`.
* **✅ Story 33.2 — Flexible Planning (The 'Swap'):** Split into two PRs due to scope.
  - **✅ 33.2a — Move session + USER_OVERRIDE in prompt:** `SuggestedWorkout` gets an optional `scheduledDate: Date?` and `isSwapped: Bool` with backwards-compatible `Codable` decode (old AppStorage plans stay intact). The `displayDate` computed picks between the override and `resolvedDate`. `TrainingPlanManager.moveWorkout(_:to:)` writes the override + re-sorts on `displayDate` so the UI moves along immediately. UI: a new "Move session" action in `WorkoutDetailView` + a day-chips sheet for the current week. AI context: the new `UserOverrideContextFormatter` produces the `[USER_OVERRIDE]` block with an explicit instruction to the coach to respect moved sessions. 5 unit tests for the formatter.
  - **✅ 33.2b — Reset Schedule button + AI replan:** A "Rewrite schedule" button in `WeekTimelineView`, only visible with ≥1 moved session. Reuses the existing `sendHiddenSystemMessage` flow with a `pendingPlanUpdateMode` flag that routes the JSON pickup to `mergeReplannedPlan(_:)` instead of `updatePlan(_:)`. The app-side merge guarantees moved sessions are leading — AI output on sacred days is filtered mercilessly (defense in depth against LLM hallucinations). `PlanResetPromptBuilder` produces ISO-dated prompts with an explicit "sacred sessions" section. A ProgressView in the button during the API call. 13 unit tests in `PlanResetPromptBuilderTests` + `TrainingPlanManagerMergeTests` cover: prompt format, sacred-sessions mention, date mismatch in the merge, empty AI output, AI overlap with a swap, sorting, motivation carry-over.
* **❌ Story 33.3 — Social Mode:** Closed without its own implementation. Functionally covered by 33.1b — when the user picks `.social` as the session type (manually or via the classifier on the Strava/HK title), the coach receives `intent.coachingSummary` ("Social session — intensity follows the group's pace, not a physiological goal. Don't judge on zone discipline but on mental recovery.") in the prompt injection. On-device validation showed this is sufficient for the coach tone. Returns to the roadmap if social rides turn out to really need their own logic (e.g. a separate UI mode, a different TRIMP multiplier, or an explicit Vibe Score coupling) — not before that need is concrete.
* **✅ Story 33.4 — Intent vs. Execution:** `IntentExecutionAnalyzer` (pure Swift) compares the planned session type + TRIMP with actual execution. Cascade: typeMismatch > overload > underload > match > insufficientData (±15% TRIMP margin). Plan type via `SessionClassifier.classifyByKeywords` (Option B — no schema change, no Gemini update). `IntentExecutionContextFormatter` produces a coach-usable `[ANALYSIS — INTENT vs UITVOERING]` block per verdict with explicit response instructions (compliment on match, recovery suggestion on overload, compensation on underload, structural caveat on a type mismatch). A Coach Comparison card in `WorkoutAnalysisView` with state-dependent colour/icon (✅ green, ⚠️ orange, 🔥 red-orange, 💧 blue — all SF Symbols). Match on the calendar day via `[SuggestedWorkout].first(matching: ActivityRecord)`. 19 unit tests cover the cascade + the 15% boundary + UI text per verdict.

---

### ✅ Epic #35: Dynamic Gemini Model Selection in Settings

Configurable Gemini models in Settings so we can dodge overload without a new app release. The catalogue is served by the Cloudflare Worker (the same pattern, with `X-Client-Token`) — the iOS app does not fetch model names directly from Google so we can validate centrally which models we support.

* **35.1 — Cloudflare Worker `/ai/models`:** endpoint live on the Worker, secured with `X-Client-Token`. Initially a static catalogue, then upgraded to a live `GET https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY` with a server-side filter (`generateContent` support, Gemini family only), a sort heuristic and a 1h cache via `caches.default`. Tests in `vibecoach-proxy/test/index.spec.js` (vibecoach-proxy PR #1 + #2, deployed).
* **35.2 — iOS Catalogue & AppStorage:** `AIModelCatalogService` fetches via `Secrets.stravaProxyBaseURL/ai/models`; `AIModelAppStorageKey.primary` / `.fallback` hold the choice. Defaults (matching production before Epic #35): `gemini-flash-latest` + `gemini-flash-lite-latest`. On an invalid stored choice (a deprecated model) the UI silently falls back to the server default.
* **35.3 — Dual-Picker UI:** Two `Picker` components ("Primary model" / "Fallback model") in `AIProviderSettingsView`. The initial load shows a `ProgressView` placeholder; the pickers appear only once the Worker fetch finishes (live or fallback). On a network error the UI silently falls back to `AIModelCatalog.builtInFallback`.
* **35.4 — ChatViewModel wiring:** `buildGenerativeModel` and `buildFallbackGenerativeModel` read the chosen model names from `UserDefaults` via `AIModelAppStorageKey.resolvedPrimary()` / `.resolvedFallback()` instead of hardcoded strings. The existing 503/429 waterfall stays unchanged.
* **35.5 — Unit + UI tests:** 12 cases for `AIModelCatalogService` (happy path, HTTP errors, decoding, transport, headers, builtInFallback, AppStorage resolvers) + 3 XCUITests for the pickers via the `-UITestOpenAICoachConfig` launch arg. PRs #185, #187, #188, #189.

**Result:** a dynamic model catalogue live in production, configurable per user, automatically in sync with Google's available models via the Worker — without needing an app release to add or deprecate models.

---

### ✅ Epic #36: Test Coverage Increase — Foundation Hardening

An authoritative coverage measurement in April 2026 showed that key services had 0% coverage despite their test files existing — the earlier README claim of 63% turned out to be unsubstantiated. This epic closed the highest-impact gaps and brought the measured full-suite coverage to **51.16%** (it had been effectively ~7-30%). Strategy: focus on pure logic with high LOC volume and/or customer-critical paths; UI Views remain limited by SwiftUI testability.

**End result per sub-task** (full-suite coverage = unit + UI tests, measured via `xcodebuild -enableCodeCoverage YES`):

| # | Target | Before | After |
|---|---|---|---|
| 36.1 | `ProgressService` + `BlueprintGap` | 0% | **95.12%** |
| 36.2 | `FutureProjectionService` (+ Periodization unlock via a pbxproj fix) | 0% | **97.07%** |
| 36.3 | `APIKeyValidator` | 0% | **67.44%** |
| 36.4 | `ProactiveNotificationService` (pure logic extracted) | 0% | **31.25%** |
| 36.5 | `FitnessGoal` enums + computed properties | 21% | **82.61%** |
| 36.6 | `KeychainService` (integration against the sim Keychain) | 1.7% | **93.10%** |
| 36.7 | README + ROADMAP updated with measured coverage | — | — |

**Sub-task details:**

* **36.1 — `ProgressService` + `BlueprintGap`:** a 1-line smoke test replaced by 41 cases covering `TRIMPTranslator`, `BlueprintGap` computed properties and `ProgressService.analyzeGaps` (incl. phase-window TRIMP accumulation and sport-specific km filtering).
* **36.2 — `FutureProjectionService` + pbxproj fix:** discovered that 49 already-written test cases never ran due to pbxproj bugs (missing `PBXFileReference` declarations + non-hex IDs). Fix + 16 new cases for `coachContext` branches.
* **36.3 — `APIKeyValidator`:** error classification extracted to a `classify(_:)` static helper; 12 cases for all `GenerateContentError`/`URLError` paths + input guards.
* **36.4 — `ProactiveNotificationService`:** 4 pure helpers extracted from the stateful singleton (`composeEngineAContent`, `composeEngineBContent`, `isCooldownActive`, `banisterTRIMP`). Ceiling at 31% because ~70% is iOS lifecycle (`HKObserverQuery`, `BGTaskScheduler`) — all user-visible notification text and the cooldown gate are now defended.
* **36.5 — `FitnessGoal` enums:** 38 new cases for `SportCategory.from(hkType:/rawString:)`, `BodyArea.severityLabel`, all enum displayName mappings, `AIProvider.isSupported`, `SuggestedWorkout.resolvedDate` (NL/EN/ISO).
* **36.6 — `KeychainService`:** 11 integration tests against the real simulator Keychain with UUID-namespaced service names. A CI flake in an adjacent test (`testSendMessage_WithInvalidAPIKeyError`) fixed at the same time by replacing a fixed `Task.sleep` with a polling loop.

**Lessons learned:**

- README coverage claims without an authoritative measurement are not reliable — before this epic the reality was significantly lower than the claimed 63%.
- Pbxproj errors can make test files disappear entirely without a visible error — the "0% coverage despite an existing test file" symptom is a red flag for pbxproj corruption.
- iOS lifecycle services (HealthKit observers, BG tasks, notification center) impose a hard ceiling on coverage; the dividing line with pure logic must be designed deliberately to make testability possible.

---

### ✅ Epic #37: Internationalisation & English-language codebase (NL + EN + DE + ES)

**Closed (June 2026).** The app is multilingual (NL/EN/DE/ES) and the whole codebase + coach prompt are English. Merged: 37.1 through 37.6 (PR #291–#306, ~530 catalog keys) + delete-goals & tap-to-edit navigation (#305). Architecture: see the Localization section in `ARCHITECTURE.md` + the i18n pattern in `CLAUDE.md`. **Deliberately not done:** native DE/ES translation review (no native speaker available — the translations are LLM-generated and functionally correct), 37.7 (the doc files themselves to English; only synced in substance — this very translation completes that for the ROADMAP) and 37.8 (per-language UI-test pass; UI tests run forced in `nl`). Polish, not a blocker.

Two related tracks, now with commitment and direction:
1. **App multilingual** — Dutch (current base) + **English, German, Spanish**, with the localisation infra (`Localizable.xcstrings`) set up so an extra language is merely a column of translations.
2. **Codebase fully English** — all code comments, all four doc files (README, ARCHITECTURE, ROADMAP, CLAUDE.md) and the in-code prompt texts to English.

The figures below are re-measured on the current codebase (May 2026; 127 Swift files, ~28k LOC) — substantially grown compared to the original analysis.

**Core insight that makes the hardest path light:** because the codebase is going to English anyway, we rewrite the AI system instruction to English once and give the model a locale-dependent **"respond in {language}"** directive. So we maintain no four translated prompt copies — the generated prose comes in the user's language, while the instruction + static context labels stay English (LLMs read those fine). This replaces the old "template the whole prompt per language" approach.

#### 37.1 — Localisation infra + UI strings

| Category | Inventory | Approach |
|---|---|---|
| `Localizable.xcstrings` | 0 (zero start) | Create a String Catalog; 4 language columns |
| SwiftUI string literals (`Text`/`Label`/`Button`/`.navigationTitle`) | **291** | extract to keys, `String(localized:)` |
| Notification texts (`ProactiveNotificationService`) | ~10 | localised keys |

Pure-Swift helpers that now return strings (formatters) get a `Locale`/key parameter instead of inline NL text. **Effort:** ~22–30h.

**Realised (✅, PR #291–#300):** String Catalog set up + language picker in Settings (37.5) + locale formatting (37.2) + runtime language switch (37.1a). Then the **`Text(String)` sweep (37.1c)**: all verbatim-rendering variable strings converted — `Text(LocalizedStringKey(var))` for shared row/card components, `String(localized:)` for computed `-> String` props. Covered: Settings, Dashboard, Goals, VibeScore, TrainingThresholds, GapAnalysis, WeekTimeline, WorkoutAnalysis, Onboarding, Sync/Blueprint/Trend widgets, ChatView coach cards + UI-only enums (Theme, phase focus). ~482 catalog keys EN/DE/ES. **Open:** sport/session-type names (`SportCategory`/`SessionType.displayName`) + HR zone + `GoalBlueprint.displayName` stay NL deliberately because they are interpolated into the coach prompts — that UI-vs-prompt split sits in **37.4**. UI tests have run forced in `nl` (`-testLanguage nl`) since then because the app is now locale-sensitive. Pattern + pitfalls recorded in memory (`project_i18n_textvar_pattern`).

#### 37.2 — Locale-aware date/number formatting

**28** places with a hardcoded `Locale(identifier: "nl_NL")` → device or chosen locale. Date names, numbers and units follow the active language. **Effort:** ~4–6h.

#### ✅ 37.3 — Multilingual AI coach (critical path, but lightened)

**Realised (✅, PR #302):** `AppLanguage.promptLanguageName` (English language name for the directive; `.system` → device language). The hardcoded "reply in Dutch" directives in `ChatViewModel` (system instruction + JSON-field instructions), `WorkoutInsightService` and `ChatScopeInstruction` replaced by a dynamic `\(replyLanguage)`. Instruction bodies stay English; only the directive steers the output language. `systemInstruction`/`text` are now computed so the language is read at call time. +3 tests; prompt test classes green (37). **Open:** the static context labels/bracket tokens (`[ACTUELE KLACHTEN]`, HARD-CONSTRAINT prose in `SymptomContextFormatter`) are still NL — going to English coincides with **37.6** (the model reads them fine, so no functional blocker).



System instruction in `ChatViewModel` (~90 lines) + ~19 context formatters/prompt builders + ~34 `Nederlands`/`nl_NL` references. Approach per the core insight:
- System instruction + static context labels **to English** (coincides with 37.6).
- Locale-dependent `respond in {language}` directive (NL/EN/DE/ES) instead of the hard "Reageer in het Nederlands".
- Dynamic values (dates, BPM, TRIMP, zones) locale-formatted via 37.2.
- JSON response keys are already English — parser unchanged; only the prose fields (`motivation`/`description`/`reasoning`) now come in the user's language.

**Effort:** ~12–16h (was 20–24h thanks to the single-prompt approach).

#### ✅ 37.4 — Language-dependent detection logic + UI label split

**Realised (✅, PR #301):**
- **UI label split**: `SportCategory`/`SessionType.displayName`, `BodyArea.rawValue` and `severityLabel` stay NL (prompt-coupled / SwiftData storage), but the View render sites resolve them via `LocalizedStringKey` / `String.LocalizationValue` → the UI shows translated text while the prompt stays stable. Closes the deliberate gap from 37.1c.
- **`BodyArea.injuryKeywords`** → NL+EN+DE+ES union (accents with/without diacritic); `SymptomContextFormatter` reuses that set (DRY) + multilingual general injury words.
- **`SuggestedWorkout.resolvedDate`** → now also parses German + Spanish day names.
- Tests: DE/ES day-name parsing (incl. accent variants) + multilingual keyword coverage.

**Open:** `BodyArea.severityLabel` stays NL in the coach *prompt* (only the UI render is localised) — full prompt language falls under 37.3.

Production logic that leans on NL words becomes per-language:
- **`BodyArea.injuryKeywords`** — injury keywords (`kuit`, `scheen`, …) → a keyword set per language (NL/EN/DE/ES).
- **`BodyArea.severityLabel`** — pain labels → localised.
- **`SuggestedWorkout.resolvedDate`** — parses day names now bilingual NL+EN; extend to DE+ES (existing per-language lookup pattern).

~21 detection hits. **Effort:** ~6–10h (four keyword sets + tests).

#### 37.5 — Language choice in Settings

An in-app language picker that overrides the device locale (default: device locale, no forced switch for existing users). Propagates via `@Environment(\.locale)` + AppStorage; may require a state reload. **Effort:** ~6–8h.

#### ✅ 37.6 — Code comments + prompt content → English

**Realised (✅, PR #303 + #304):**
- **Part 1 (#303)** — prompt *context layer*: all ~24 structural bracket tokens (`[ACTUELE KLACHTEN]`→`[CURRENT COMPLAINTS]`, …) consistently NL→EN at every emit and reference site, plus the prose of all 9 context formatters. Remaining code comments → English.
- **Part 2 (#304)** — coach *core* prompt: `ChatViewModel` systemInstruction examples/inline instructions, `PeriodizationEngine` + `TrainingPhase` periodisation prose, `SessionType.coachingSummary`, sentinel, markers. **Latent bug fix along the way:** translating the emitters created marker mismatches (systemInstruction still looked for NL markers while the emitters were English) — all markers now synchronised. User-facing chat/fallback/error messages → `String(localized:)` (the user sees them).

The full prompt is now English; the output language is steered solely via the `respond in {language}` directive (37.3). Variable/function names were already English (Swift convention).

#### 37.7 — Documentation → English + flip project rules

README, ARCHITECTURE, ROADMAP, CLAUDE.md to English, plus the derived `architecture.json`/`.html`. **Important:** this flips two standing CLAUDE.md rules — §5 ("comments in Dutch") and §10 ("reply in Dutch") — which are rewritten to English as part of this epic. **Effort:** ~16–24h.

#### 37.8 — Test suite i18n

UI tests currently use hardcoded NL assertions (`"Goedemorgen…"`, `"Doelen"`). Per language, a forced locale fixture (launch arg `-AppleLanguages (xx)`) or assertions against localisation keys instead of literal text. **Effort:** ~12–16h.

#### Translation production

EN/DE/ES translations of ~291 UI strings + notifications: LLM-assisted generation into the xcstrings, then **native review** for DE + ES (tone/idiom). **Effort:** ~16–24h.

#### Found & fixed during device testing (✅)

Besides the planned stories, German device tests surfaced concrete bugs/gaps that were fixed right away:
- **Week schedule collapsed onto 1 day** (#302): the German coach gave day names like "Sonntag, 7. Juni"; `resolvedDate` failed on the comma → all workouts fell back to today. Fix: strip punctuation + DE/ES day names.
- **`activityType` stayed Dutch** in a German UI (#302): instruct the coach to write activityType in the user's language + a language-independent `SuggestedWorkout.isRestDay`/`.kind` classification (rest/sport icon/badge now work in every language).
- **Format-key mismatch** in Dashboard banners (#302): catalog keys with `%@` while Int interpolation generated `%lld` → NL fallback. Fix: pre-format numbers as String (`%@`).
- **Delete goals** (#305): there was no way to delete a goal — a destructive button + confirmation in `EditGoalView`.

#### ✅ Backlog item completed elsewhere: multi-day events first-class

This idea was fully worked out and delivered as **Epic #55** (Multi-day events first-class) + **Epic #56** (location-aware per-stage weather) — see the [archive](ROADMAP-archive.md). Kept here only as a cross-reference.

#### Effort overview

| Component | Hours |
|---|---|
| 37.1 infra + UI strings | 22–30h |
| 37.2 locale formatting | 4–6h |
| 37.3 AI coach i18n | 12–16h |
| 37.4 detection logic | 6–10h |
| 37.5 language-choice UI | 6–8h |
| 37.6 comments → English | 30–40h |
| 37.7 docs → English + rules | 16–24h |
| 37.8 test i18n | 12–16h |
| Translation production + native review | 16–24h |
| QA across 4 languages | 12–20h |
| **Total** | **~136–194h** (~4–6 sprints) |

#### Recommended phasing (sprints)

1. **English codebase first** (37.6 + 37.7 + 37.3 prompt-to-English). Directly yields a consistent English-language base; the coach stays functional (English) and it is the natural preparation for i18n. Low runtime risk.
2. **i18n foundation** (37.1 + 37.2 + 37.5): xcstrings, all UI strings extracted, locale formatting, language-choice UI — with only NL+EN filled for now.
3. **Coach + detection multilingual** (37.3 directive + 37.4): respond-in-language + per-language keyword sets.
4. **Turn languages on** (translation production DE+ES + 37.8 test i18n + QA): fill the DE/ES columns, native review, locale-fixture tests.

#### Blockers and risks

- **Coach tone per language** — `respond in {language}` works well, but DE/ES tone only manifests in production; a native spot check is recommended before release.
- **Backwards-compat** — the default stays `Locale.current`; existing NL users notice nothing until they pick a language themselves.
- **Git blame** — 37.6 (~4,300 comment lines) spread over batches/PRs to keep review manageable.
- **CLAUDE.md rule change** — flipping §5/§10 touches how the assistant itself works; deliberately explicit in 37.7 so it does not become a creeping inconsistency.

**Status:** ✅ — closed June 2026 (see heading): 37.1–37.6 merged (PR #291–#306). The remaining i18n polish — 37.7 (the doc files themselves to English), 37.8 (per-language UI-test pass) and native DE/ES translation review — was deliberately not carried out and is not a blocker.

---

### ✅ Epic #38: HealthKit Permission UX & Sync Reliability

Trigger: a real user (April 2026) did an app reinstall after which iOS had partially reset the HealthKit permission — Workouts/HRV/Cardio Fitness were off. The auto-sync 'succeeded' technically (HealthKit returns no error on partial permissions), but fetched 0 workouts. Result: goals at 0 TRIMP/0 km, a "Adjustment needed" banner, the coach suddenly no longer knew the athlete. A silent failure — the worst UX. This epic catches two related gaps: proactively request all permissions, and make it visible when a sync yields suspiciously little.

* **✅ 38.1 — Bundle permission request:** Single source of truth in `HealthKitPermissionTypes` (`readTypes`, `writeTypes`, `critical` subset). Both existing auth methods on `HealthKitManager` (`requestOnboardingPermissions` + `requestAuthorization(completion:)`) now read from it — no more drift between "what we request" and "what we check". `.activeEnergyBurned` added (was missing before). A new `requestPermissionsForCriticalNotDetermined()` async helper retriggers via `AppTabHostView.onChange(of: scenePhase)` on the `.active` transition when at least one critical type (`workout`, `heartRate`, `hrv`, `activeEnergy`) is `.notDetermined` — only-`.notDetermined` mitigates the risk of unexpected prompts for existing users.
* **✅ 38.2 — "Silent sync" detection + banner:** `HealthKitSyncService.syncHistoricalWorkouts(to:)` now returns the workout count from the 365d window; `AppTabHostView.runHealthKitAutoSync` and `SettingsView.runHealthKitHistoricalSync` cache it to `UserDefaults("vibecoach_lastHKWorkoutsCount")`. The pure-Swift `HealthKitSyncStatusEvaluator.shouldWarn(workoutCount:workoutAuthStatus:)` (4 unit tests) determines the banner condition strictly: `count == 0 && authStatus != .sharingAuthorized`. A new `HealthKitPermissionWarningBanner` on `DashboardView` renders via the `DashboardBannerView` wrapper (red, `exclamationmark.icloud` icon, an "Open Settings" button → `UIApplication.openSettingsURLString`). Partial permission (workouts yes, HR no) is deliberately out of scope — it manifests itself in empty HR charts.
* **✅ 38.3 — Reinstall scenario:** Implicitly covered via 38.1's `scenePhase = .active` retrigger — on every foreground return the app checks whether crucial types are `.notDetermined` and re-requests only those. A separate `firstLaunchAfterInstall` flag and a one-off onboarding tip from the original story turned out to be redundant: the more general mechanism covers the reinstall scenario and other paths by which iOS permissions become `.notDetermined` (e.g. a Privacy & Security reset).

**Effort realised:** ~3h in one PR. 38.1 was a refactor + a new helper (~1h), 38.2 a pure-Swift evaluator + a new banner component (~1h), 38.3 fell within 38.1 (~0h extra).

**Status:** ✅ — closed (May 2026). Bundle permission, silent-sync detection and the foreground retrigger land together in one multi-story PR per `feedback_epic_pr_workflow`. On-device validation: a reinstall test with a partial iOS permission reset → the banner appears + "Open Settings" opens the right panel directly.

---

### ✅ Epic #39: Swift 6 Strict Concurrency Cleanup

Trigger: Xcode reported 72 warnings around actor isolation in `ChatView.swift` and `FitnessDataService.swift` (April 2026). The warnings were non-blocking, but Swift 6 (strict concurrency = complete) turns them into hard compile errors. Tech debt to pay off before we hit a wall on a new Xcode/Swift version.

**Sub-stories:**

* **✅ 39.1 — Make `Logger` static properties cross-actor accessible (70 warnings → 0):** `AthleticProfileManager.logger` sat as a `static let` on a `@MainActor class` and was therefore implicitly main-isolated; every reference from a `@Sendable` HK callback (HRV, sleep, sleep stages) gave a warning. The new `AppLoggers` enum (`Services/AppLoggers.swift`) bundles loggers in a nonisolated namespace. `Logger` is internally thread-safe — actor isolation around it adds nothing. For now one entry (`athleticProfileManager`); subsequent loggers migrate when they too get in the way.
* **✅ 39.2 — `themeManager.primaryAccentColor` in a `PhotosPicker` label (2 warnings → 0):** The `PhotosPicker` label closure is `@Sendable` and was not allowed to read the main-actor property directly. Fix: read the colour into a local `let accentColor` before the closure, then capture `accentColor`.
* **→ 39.3 — moved to Epic #62 (story 62.6).** The project setting "Strict Concurrency Checking" to `Complete`: optional, enforces that future PRs introduce no new regressions. Detached from this cleanup because it may surface new Sendable warnings; picked up as a standalone PR under Epic #62.

**Effort realised:** ~1h. Pure type-system tweaks; all 542 tests stay green. The build goes from 78 → 7 warnings (the 6 remaining are iOS 13 deprecations on `HKQuantitySeriesSampleQuery.init(sample:quantityHandler:)` — non-concurrency, a separate hygiene PR).

**Status:** ✅ — core (39.1 + 39.2) live and merged. The optional build-setting promotion (39.3) is pushed forward to **Epic #62** (remaining hardening).

---

### ✅ Epic #40: Strava Power-Stream Ingest

Trigger: a user with a Garmin power meter (April 2026) discovered that `cyclingPower` was missing in vibecoach even though his rides do show power in Strava. Strava namely syncs **no** stream data (power, cadence, velocity) to Apple Health — only workout events and average HR. As a result the `WorkoutSample` pipeline (story 32.1) misses a whole class of cycling data.

**Sub-stories:**

* **✅ 40.1 — Strava `/streams` API call:** `FitnessDataService.fetchActivityStreams(for:)` fetches `time`, `watts`, `cadence`, `heartrate`, `velocity_smooth` via `?keys=...&key_by_type=true`. The token flow reuses the existing Strava OAuth.
* **✅ 40.2 — Deterministic UUID instead of a schema change:** `UUID.deterministic(fromStravaID:)` (SHA256, UUIDv5-like) derives a fixed UUID for Strava records. `WorkoutSample.workoutUUID` stays `UUID` — no migration. `UUID.forActivityRecordID(_:)` is the central router (HK uuidString or Strava fallback).
* **✅ 40.3 — `StravaStreamIngestService`:** a mirror of `WorkoutSampleIngestService` (kept separate so as not to pollute the HK logic). Reuses `SampleResampler` with identical strategies (average for HR/power/cadence, linear interpolation for speed). Idempotent via `WorkoutSampleStore.replaceSamples`. Backfill in the `DashboardView` scenePhase flow for the last 10 Strava records without samples, with a 100ms throttle. `WorkoutAnalysisView` now uses `UUID.forActivityRecordID` so the Strava detail view automatically shows the power chart once samples are in. Plus `StravaActivity.device_watts: Bool?` (decodeIfPresent — backwards-compat with existing caches). 14 unit tests.
* **✅ 40.4 — Classifier reclassifies after stream ingest:** `SessionReclassifier` (pure-Swift, mirror of the `ActivityDeduplicator` pattern) runs in the same scenePhase flow directly after the auto-dedupe. Records that just got samples (Strava backfill 40.3 or HK DeepSync 32.1) get the zone-distribution proposal; records without samples are skipped because the avg-HR fallback already ran at ingest. Plus `ActivityRecord.manualSessionTypeOverride: Bool?` (lightweight migration) — set by `WorkoutAnalysisView.setSessionType` so a manual choice is never overwritten by the rerun. `WorkoutSampleStore` got a `samples(forWorkoutUUID:)` getter (sorted by timestamp). 6 unit tests.

**Status:** ✅ — all four sub-stories live. The pipeline from Strava API → SwiftData record → stream backfill → dedupe → reclassify is end-to-end self-regulating; new rides automatically get a correct sessionType once their samples are in.

---

### ✅ Epic #41: Dual-Source Single-Record-of-Truth

Trigger: during on-device validation of Epic #40 (April 2026) it turned out that a Garmin ride lands in SwiftData both via Apple Health (workout + HR, no power) and via Strava (full with power) as separate `ActivityRecord`s. The existing `removeDuplicateRecords` debug button in Settings (`startDate + sportCategory` composite key) was source-blind: the HK record survived, the Strava record (with power!) was deleted.

**Sub-stories:**

* **✅ 41.1 — Source-aware dedupe priority:** `ActivityDeduplicator` (pure-Swift) groups records on a composite key (startDate ±5s + sportCategory) and picks the "richest" within each group via heuristic: samples > deviceWatts > trimp > avgHR > stable tiebreaker. Auto-dedupe in the `DashboardView.scenePhase` flow directly after the Strava stream backfill — the user does nothing, the DB stays self-cleaning. 10 unit tests cover all paths + edge cases.
* **✅ 41.2 — `deviceWatts` on `ActivityRecord`:** An optional `Bool?` added (lightweight migration). Filled from `StravaActivity.device_watts` in both sync paths (`AppTabHostView.performAutoSync` + `SettingsView.syncHistoricalData`). For HK records `nil` (no device meta info available). Works as a strong signal for the dedupe heuristic — even before the stream backfill the helper already knows which record will be richer.
* **✅ 41.3 — OAuth hardening (`ensureValidToken()`):** A central guard on `FitnessDataService` that checks the token before every API call and refreshes via the proxy on (near-)expiry. Five internal callers (latest/byId/streams/recent/historical) now route through this one function — an empty or missing access token throws `.missingToken` instead of a silent 401 further down the pipeline. 4 new tests cover fresh-token, refresh-on-expiry, missing and empty token.
* **✅ 41.4 — Ingest-side prevention (`smartInsert`):** `ActivityDeduplicator.smartInsert(_:into:)` does a three-layer check at ingest: (1) source-id idempotent, (2) ±5s window cross-source comparison via `shouldReplace`, (3) regular insert. A poorer HK record never overwrites a richer Strava record with deviceWatts again — regardless of order. Applied in `HealthKitSyncService`, `AppTabHostView` (Strava auto-sync) and `SettingsView` (Strava historical sync). The manual "Remove Duplicate Activities" button in Settings (DEBUG) removed — auto-dedupe + smart-ingest cover both sides. 8 race tests in `SmartIngestRaceTests` guarantee order independence.

**Status:** ✅ — closed (April 2026, PR #222). The user no longer needs the dedupe button; smart-ingest prevents impoverishment at the front door and auto-dedupe cleans up any leftovers during the scenePhase flow. This decouples Epic #42 (Always-on Dual-Source Sync) — the dedupe layer is robust enough to run both sources side by side continuously.

---

### ✅ Epic #42: Always-on Dual-Source Sync

Trigger: after on-device validation of Epic #41 (April 2026) the user asked whether HealthKit could be set as the primary source again. Answer: *technically yes, but then the Strava fetch stops and you miss power for new rides.* In `AppTabHostView.performAutoSync` (and `SettingsView.syncHistoricalData`) there was an if/else on `selectedDataSource`: if HK was primary, the Strava path was skipped entirely. That was an artefact from the time when one source had to be leading — since Epic #41 we have a dedupe layer that handles multiple sources, so the exclusivity of the toggle behaviour had become redundant.

**Sub-stories:**

* **✅ 42.1 — Decouple sync paths from the toggle:** `AppTabHostView.performAutoSync` and `SettingsView.syncHistoricalData` are split into `runHealthKit*Sync()` + `runStrava*Sync()` helpers that run concurrently via `async let`. `selectedDataSource` is no longer read in the sync layer. Cross-source duplicates are caught by `ActivityDeduplicator.smartInsert` (Epic #41). On a missing Strava token the auto-sync is silently skipped — no every-launch noise in the console.
* **✅ 42.2 — Redefine the semantics to a source preference:** The Settings section "PRIMARY DATA SOURCE" renamed to "SOURCE PREFERENCE"; the helper text explains that both sources always sync and the toggle only determines which source the coach addresses first. The Connection cards in Settings show "Preference" / "Supplementary" instead of "Primary" / "Backup".
* **✅ 42.3 — Backwards-compat:** the `@AppStorage("selectedDataSource")` key + `DataSource` enum cases + raw values unchanged, so existing users keep their toggle state without a reset or re-login prompt.

**Effort realised:** ~1h. 4 files (AppTabHostView, SettingsView, README, ROADMAP). All 30 regression tests green.

**Status:** ✅ — closed (April 2026). The user can pick HK as the source preference without losing Strava power. Tiebreaker bias in `ActivityDeduplicator` based on the source preference is deliberately kept out of scope; the pure-Swift helper stays AppStorage-independent and the current id-tiebreaker is deterministic enough.

---

### ✅ Epic #43: UI Polish — Settings status & Layout consistency

Trigger: during on-device use (April 2026) it stood out that (a) the three "Connections" cards in `SettingsView` (HealthKit, Strava, AI Coach) showed hardcoded sublabels (`"Primary · Live"`, `"Backup"`, `"Gemini"`) that did not move with the real connection state or the source toggle, and (b) the "Good evening" title on `DashboardView` partly disappeared under the iPhone status bar while the other tabs (Settings, Goals, Coach, Memory) did respect that space correctly.

**Sub-stories:**

* **✅ 43.1 — Dynamic Connections cards in Settings:** Three computed properties in `SettingsView` (`healthKitConnectionSubtitle`, `stravaConnectionSubtitle`, `aiCoachConnectionSubtitle`) now reflect the real state. HealthKit and Strava show "Primary"/"Backup" depending on `selectedDataSource`, or "Not connected" when the source is not authorised. AI Coach shows the short provider name (Gemini / OpenAI / Anthropic) and — only for Gemini — also the chosen model from Epic #35 (e.g. "Gemini · flash-latest"). No change to `SettingsConnectionCard` itself; the binary green/grey dot stays as it was. A full tri-state (orange for partial-auth) comes with Epic #38 (HealthKit Permission UX).
* **✅ 43.2 — Fix the Dashboard title under the status bar:** `DashboardHeaderView` lacked the `.padding(.top, 56)` that all other tab views (`SettingsView`, `GoalsListView`, `ChatView`, `PreferencesListView`) did have. One line added; the visual hierarchy of the other views unchanged.

**Effort realised:** ~30 min. 43.2 was a one-liner; 43.1 was three computed properties + one extra `@AppStorage` binding for the Gemini model name. No new tests — the existing 542-test suite stays green, and the logic in the computed properties is simple enough to verify visually.

**Status:** ✅ — both stories live. A possible tri-state extension (orange dot on partial HealthKit auth) follows with Epic #38.

---

### ✅ Epic #44: Personal HR Zones & FTP

Trigger: during on-device validation of Epic #32 story 32.3b (April 2026) the `WorkoutPatternDetector` turned out to report three significant "red" patterns on a calm social ride (decoupling 102%, cardiac drift 13%, slow HR recovery 11 BPM). The decoupling bug was repaired with a steady-state-CV gate, but the underlying problem remains: **all thresholds are population averages** (Joe Friel / TrainingPeaks norm + Tanaka maxHR), while this user has higher zones than an average 35-year-old (zone 2 = 139–157 BPM). A Z2 ride looks like a Z3 effort to the detector and the Coach analysis judges too harshly.

Besides the detector, FTP impacts `SessionClassifier` (zone-distribution classification of power data), `ChatViewModel.buildContextPrefix` (the coach must interpret "calm" differently for this user) and the coaching tone in general.

**Sub-stories:**

* **✅ 44.1 — Foundation: `ThresholdValue` + zone calculators (PR A):** `UserPhysicalProfile` extended with optional `maxHeartRate`, `restingHeartRate`, `lactateThresholdHR` and `ftp` fields — each a `ThresholdValue { value, source }` with `ThresholdSource.automatic / manual / strava`. Backwards-compat via an explicit init with defaults. `effectiveMaxHeartRate` falls back to Tanaka(`ageYears`) and `effectiveRestingHeartRate` to 60 BPM so all existing consumers keep working. Persistence in `UserProfileService` via four `vibecoach_*.v1` UserDefaults keys + `cachedThreshold` / `saveThreshold` / `storeAutoDetectedThresholds` helpers (the last respects `manual` over `automatic` by default). Pure-Swift `HeartRateZoneCalculator` (Karvonen + Friel-LTHR, both 5 zones) and `PowerZoneCalculator` (Coggan 7-zone model with an open Z7) deliver `[HeartRateZone]` / `[PowerZone]` with a `zoneIndex` lookup for detector gates.
* **✅ 44.2 — Automatic detection from HK history (PR A):** `PhysiologicalThresholdEstimator` (pure-Swift, AppStorage-free) derives three thresholds from a collection of `WorkoutHRSample` + daily resting-HR samples: **max HR** as the highest 95th percentile across all eligible workouts (>20 min, >30 samples, plausibility filter 80-220 BPM), **resting HR** as the median over plausible daily HK samples (30-100 BPM, minimum 14 days), **LTHR** as the highest 30-min rolling-window average from the heaviest workout. The caller does the HK fetch itself and passes the samples in — an adapter layer follows in 44.4 once the Settings UI can trigger the detection. 51 unit tests cover the zone calculators, estimator, threshold persistence and effective fallbacks.
* **✅ 44.3 — Strava FTP import (PR B):** `FitnessDataService.fetchAthleteFTP()` fetches FTP via `/api/v3/athlete` with the existing OAuth — a minimal `StravaAthlete` DTO with only `ftp: Int?` (no extra PII). Called by the Settings UI to store the FTP with source `.strava`. Own detection from power streams (classic 20-min-avg × 0.95) is deliberately kept out of scope — Strava's own value wins and manual entry wins over both.
* **✅ 44.4 — Settings UI + HK adapter (PR B):** A new `TrainingThresholdsSettingsView` (NavigationLink target under "TRAINING THRESHOLDS" in Settings) with four row cards (Max HR / Rest HR / LTHR / FTP), a source badge per card ("Auto · from HK history", "Manual", "Strava"), an edit sheet with a number field + clear button, two action rows ("Detect from HK history", "Import FTP from Strava"), and a live zone-preview card at the bottom (Friel-LTHR or Karvonen for HR; Coggan for power). The adapter layer `PhysiologicalThresholdService` wraps `PhysiologicalThresholdEstimator` with the actual HK queries — workouts from the past 6 months + daily `restingHeartRate` samples, a bucket resampler to 60s buckets for LTHR.
* **✅ 44.5 — Detector and classifier calibration (PR C):** `WorkoutPatternDetector.detectCardiacDrift` and `detectHeartRateRecovery` accept an optional `zones: [HeartRateZone]?` parameter. Cardiac drift only triggers when the avg HR falls in Z1-Z3 (a real aerobic effort) — Z4/Z5 drift is expected behaviour. HR recovery requires a peak in Z3+ — recovery from a Z2 peak is not an informative signal. The new `detectAll(in:profile:)` overload derives zones from `UserPhysicalProfile` (Friel if an LTHR is present, otherwise Karvonen) and threads them through. The backwards-compat default nil keeps population-global behaviour intact for callers without a profile. `WorkoutAnalysisView` and `DashboardView.refreshWorkoutPatternsContext` now use the profile-aware variant. `SessionClassifier` gets an optional `lactateThresholdHR` init parameter; `classifyByZoneDistribution` switches to Friel percentages (<81/81-89/90-93/94-99/100+) when an LTHR is present.
* **✅ 44.6 — Coach-prompt context (PR C):** A new `[TRAININGSDREMPELS]` block in `ChatViewModel.buildContextPrefix` with max/rest/LTHR/FTP + source badges + explicit Z2/Z3 boundaries ("Z2 = 142-158 BPM, Z3 = 158-165 BPM"). Behaviour rules in the block: always interpret "calm" in the context of these thresholds, link a BPM number to a zone in subjective feedback, use concrete boundaries in plan adjustments. Omit it entirely if no thresholds are set — then the coach keeps its population assumptions.

**Effort realised:** ~6-8h across three PRs (#226 / #229 / #230). 44.1 + 44.2 are pure-Swift + tested (~2h), 44.3 was ~30 min research + an import call, 44.4 was the largest in UX (~2h), 44.5 + 44.6 are refactors that update tests (~2-3h).

**Status:** ✅ — closed (April 2026, PR #226 + #229 + #230). Realised in three PRs: foundation (`ThresholdValue` + zone calculators + `PhysiologicalThresholdEstimator`), Strava FTP + Settings UI + HK adapter, and detector/classifier calibration + coach-prompt context. Verified on-device via the Epic #45 prompt dump: the `[TRAININGSDREMPELS]` block is injected correctly and the detector gates respect the personal profile — Z2 rides no longer trigger as a false-positive significant pattern.

---

### ✅ Epic #45: Per-workout context in the schedule- and goal-analysis prompt

Trigger: after Epic #44, personal training thresholds (max/rest/LTHR/FTP + zones) are already injected into every AI call by `ChatViewModel.buildContextPrefix`, and there is a 1-line `workoutPatternsContext` for the past 7 days ("Recent workout(s) show: aerobic decoupling, cardiac drift."). For schedule building and goal analysis, though, that single line is too thin — the coach cannot base specific references on it ("like in your threshold run last Tuesday…"). With richer per-workout context the AI can propose better-substantiated plan adjustments.

**Sub-stories:**

* **✅ 45.1 — `WorkoutHistoryContextBuilder` (pure-Swift):** Builds a 1-line-per-workout block of the past 14 days — date (NL locale), sport, sessionType, duration, TRIMP, avg HR, optional avg W, and the detector output as an inline suffix (severity + kind, reusing `WorkoutPatternDetector.detectAll(in:profile:)`). A pure-Swift `enum` with injected `WorkoutEntry` DTOs — the caller (DashboardView) does the async sample fetch. Sorted newest→oldest. An empty array → `""` so the whole block falls away. 5 unit tests in `WorkoutHistoryContextBuilderTests`.
* **✅ 45.2 — Injection in `buildContextPrefix`:** A new `[RECENTE TRAINING — 14 DAGEN]` block in the chat context prefix directly after the 7d pulse, with 5 behaviour rules: specific date references, a ≥3-consecutive-patterns trigger for sub-LTHR suggestions, only-on-reflection/schedule/goal-analysis, zone terminology consistent with `[TRAININGSDREMPELS]`, and injury weighting via `[ACTUELE KLACHTEN]`.
* **✅ 45.3 — Cache + refresh consolidation:** A `@AppStorage("vibecoach_workoutHistoryContext")` cache in `ChatViewModel`. `refreshWorkoutPatternsContext()` is refactored into a shared `refreshChatContextCaches()` that runs the loop over `activities` once and fills both the 7d pulse and the 14d rich cache from the same `[WorkoutEntry]` array — halving SwiftData fetch I/O and preventing double detector calls.

**Tradeoff:** more tokens per AI call → slightly higher API cost and a marginally higher safety-filter risk (long prompts can rarely be content-blocked). For power users who seriously tune the schedule, the gain (specific, substantiated advice instead of generic assumptions) far outweighs the cost.

**Status:** ✅ — implemented on the branch `feature/epic-45-workout-history-context` (3 stories in one PR per `feedback_epic_pr_workflow`).

---

### ✅ Epic #46: GitHub Actions DAG Visualisation & Pipeline Extension

Trigger: the GitHub Actions Summary tab renders a visual DAG of jobs once a workflow consists of multiple jobs with `needs:` relations (see the reference screenshot of a full-stack web app: Build → Tests → Deploy → Smoke). Right now VibeCoach has one monolithic `Build & Test` job in `ios-tests.yml` plus a separate `CodeQL` workflow — no visualisation because there is nothing to chain. Goal of this Epic: split the iOS pipeline into decoupled jobs for visual insight and parallelisation, without bringing in the complexity of signing/secrets. Backlog stories keep heavier extensions (TestFlight, snapshot tests, dependency scan) visible for the moment concrete pain arises.

**Scope choice:** the screenshot shows a web-app pipeline with deploy-to-acceptance/production and Playwright. That pattern is not 1-to-1 applicable — App Store distribution via TestFlight requires an Apple Developer account, an App Store Connect API key and signing certs in GitHub Secrets. Those are in the backlog (46.B1), not in the main scope.

**Sub-stories (low-threshold — no extra secrets):**

* **✅ 46.1 — Split `ios-tests.yml` into `unit-tests` + `ui-tests` jobs:** Two separate jobs on `macos-latest`. `unit-tests` runs `xcodebuild test` with `-only-testing:AIFitnessCoachTests`, `-enableCodeCoverage YES` and `-resultBundlePath UnitTests.xcresult`; the bundle is uploaded via `actions/upload-artifact@v4` (`if: always()`, 7-day retention) so both debugging-on-failure and the coverage job have access. `ui-tests` has `needs: unit-tests` and `-only-testing:AIFitnessCoachUITests`. Tradeoff: 2× macOS runner time per push, but a UI failure can no longer delay unit-test feedback. Also cleaned up: a duplicate `Setup Secrets` step that happened to work on case-insensitive macOS with the wrong-casing path (`Secrets-Template.swift`); `actions/checkout@v3` → `@v4` for consistency with `codeql.yml`. **Side catch:** UI tests previously did not run on CI at all — `AIFitnessCoachUITests` had `IPHONEOS_DEPLOYMENT_TARGET = 26.2` (Xcode default, never lowered) so `xcodebuild test` without `-only-testing` silently skipped them on an 18.x simulator. Lowered to 18.0 in `project.pbxproj` (matching the main app + unit tests; no `@available iOS 26` call sites). **The UI-tests job is hard-blocking** since 46.4 distinguished the root causes: parallel-disable eliminated the runner-clone flakiness and the remaining 3 failures turned out to be test-code bugs (a hidden V2.0 NavigationBar, a `.textField` lookup for SwiftUI's `.textView` rendering, too-short timeouts). `xcodebuild test` runs sequentially (`-parallel-testing-enabled NO`); `-resultBundlePath UITests.xcresult` + CoreSimulator logs stay available as artifacts for future debugging.
* **✅ 46.2 — Parallel `lint` job (SwiftLint):** A two-step approach realised. **Prep PR `chore/swiftlint-cleanup` (#246)** created `.swiftlint.yml` and resolved existing violations: a SwiftLint v0.63.2 dry-run gave 938 violations (460 line_length, 171 identifier_name, 78 comma, 54 colon, …). The config disabled noisy style rules that add no value in this codebase (line_length / identifier_name / *_length rules / cyclomatic / multiple_closures_with_trailing_closure / large_tuple etc). `swiftlint --fix` did 209 auto-fixes; the remaining 4 (3 for_where + 1 unused_optional_binding) resolved by hand. **0 force-unwrap rules** in this prep — 77 violations would warrant a separate audit PR (`chore/force-unwrap-audit`) because most of it is benign idiom. **Lint-job PR `feature/epic-46-swiftlint-job`** adds a `lint` job to `.github/workflows/ios-tests.yml` without `needs:` (runs parallel to unit-tests) on `macos-latest` (SwiftLint pre-installed). `swiftlint --strict --reporter github-actions-logging` upgrades warnings to errors so 1 new violation breaks CI; the `github-actions-logging` reporter gives inline annotations on the PR diff.
* **✅ 46.3 — `coverage-report` job as a PR artifact:** Hangs on `needs: unit-tests` and downloads the `UnitTests.xcresult` bundle from 46.1. Runs `xcrun xccov view --report --json` and transforms it via `jq` into a per-target markdown table (filtering out `*Tests.xctest` bundles). Uploaded as a `coverage-report` artifact with 30-day retention. PR-comment injection is deliberately not included — it requires `pull-requests: write` permission and is easy to add later when we want to escalate the markdown output.
* **✅ 46.4 — UI Tests CI flakiness root-cause investigation:** Two causes distinguished via xcresult-artifact analysis on `ci/investigate-uitest-flakiness`. **(1) Runner-clone flakiness** — `AIFitnessCoachUITests.xctest` had `parallelizable = "YES"` in the scheme, xcodebuild spawned multiple xctrunner clones (visible as "Clone 2 of iPhone 16 Pro" in the logs) and the clone spawning gave an intermittent `ipc/mig server died` (Mach-308). 4 tests flaked randomly. Fix: `-parallel-testing-enabled NO` at CI level (the scheme config stays `YES` for local speed). Result: 4 flaky tests → 0. **(2) Test-code bugs** — three tests failed deterministically, turned out not to be a runner issue but existing bugs that never showed before because UI tests were silently skipped before 46.1 due to the iOS 26.2 deployment-target mismatch. Fixes: `testNavigateToSettingsTab` looked for `app.navigationBars` in a view that has the V2.0 `.toolbar(.hidden)` → replaced by a `SettingsVersionLabel` identifier. `testCoachMemory` looked for `.textField` for SwiftUI's `TextField(axis: .vertical)` which renders as `.textView` → replaced by `.any` element matching. `testNavigateToCoachTab` had an 8s timeout on a view whose `onAppear` refreshes SwiftData/AppStorage caches → raised to 20s (and `testCoachMemory` to 15s) for CI launch time. Diagnostic tooling (the xcresult artifact, CoreSimulator logs) stays in the workflow for future debugging. **End result:** `continue-on-error: true` removed from the ui-tests job; UI tests now really block CI on regressions.

**Backlog (keep visible, no commitment):** — *promoted (June 2026) to the live **[Epic #63](ROADMAP.md)** as stories 63.1–63.6, where each has grounded acceptance criteria + dependencies. The list below is the original Epic #46 rationale, kept for history.*

* **⏳ 46.B1 — TestFlight deploy job on merge to main:** A `deploy-testflight` job with `needs: [unit-tests, ui-tests]` and `if: github.ref == 'refs/heads/main'`. Requires a one-off setup: an Apple Developer account, an App Store Connect API key (`.p8`), a signing cert + provisioning profile in GitHub Secrets, and `fastlane match` or `xcodebuild -exportArchive` with an `ExportOptions.plist`. Effort: ~4–6h one-off for the cert setup + workflow syntax, then maintenance-free. Pickup trigger: the user wants to automate the App Store Connect TestFlight flow instead of manually uploading an archive.
* **⏳ 46.B2 — Snapshot tests via `swift-snapshot-testing`:** PointFree's library for view snapshots (PNG diff on critical screens: Dashboard, Goals, Chat, Settings). A `snapshot-tests` job with `needs: unit-tests`. The first run generates reference images that are checked into the repo; after that CI fails on visual regressions. Effort: ~6–8h (integrate the library + write 5–10 reference snapshots). Pickup trigger: a UI regression not caught by the existing XCUITests.
* **⏳ 46.B3 — Dependency vulnerability scan:** GitHub's `dependency-review-action` on PRs that touch `Package.swift`/`Package.resolved`. Compares new transitive deps with the GitHub Advisory Database. Effort: ~30 min. Pickup trigger: Swift Package Manager is actively used for third-party deps (currently minimal — only existing Anthropic/Strava couplings via REST).
* **⏳ 46.B4 — Performance regression checks:** Build-time tracking (parsing `xcodebuild` output) and/or a light `XCTMetric` baseline (launch time, dashboard render) as its own job with a historical artifact comparison. Effort: ~4h. Pickup trigger: the user reports subjective slowness and we want objective baselines.
* **⏳ 46.B5 — Concurrency-strict build as a matrix cell:** Building on Epic #39 story 39.3 — a matrix cell that builds with `SWIFT_STRICT_CONCURRENCY=complete` so new Sendable warnings surface as a CI fail, without breaking the main build. Effort: ~1h once 39.3 itself is done.
* **⏳ 46.B6 — Semver versioning via `release-please` + git-tag-based `MARKETING_VERSION`:** Release mechanics, usable independently of 46.B1 (a tag + GitHub Release have standalone value as release history). Three sub-steps: (1) a `googleapis/release-please-action` workflow on main; the bot opens a Release PR that accumulates until you merge it — on merge it automatically creates the git tag (`v1.2.3`) + a GitHub Release with changelog. Patch/minor/major derived from Conventional Commits prefixes (`fix:` / `feat:` / `feat!:`). (2) A Run Script Build Phase that sets `CFBundleShortVersionString` at build time from `git describe --tags --abbrev=0`, parallel to the existing `CFBundleVersion = git rev-list --count HEAD` approach. One source of truth (the tag), no `MARKETING_VERSION` mutation in `project.pbxproj` needed — that file keeps its `skip-worktree` flag (CLAUDE.md §9). (3) Formalise Conventional Commits in CLAUDE.md §8 as a hard rule — already followed in practice, but release-please relies on consistency. Effort: ~2-3h one-off. Pickup trigger: the first real release (TestFlight friendly-users or App Store), or earlier if you want to make release history explicit before the first release goes out.

**Effort realised (46.1 + 46.2 + 46.3 + 46.4):** ~7h — 46.1+46.3 in PR #244 (~3h, of which ~2h first-pass UI-tests debugging), 46.4 in PR #245 (~2h, data-driven xcresult analysis + 3 test fixes), 46.2 in PR #246 (prep, ~1.5h) + the lint-job PR (~30 min).

**Status:** ✅ — all main-scope stories (46.1–46.4) live. The backlog stories (46.B1–B6) stay available for pickup when their trigger arises.

---

### ✅ Epic #47: Pause-based HR recovery

Trigger: during on-device validation of a 2-hour cycling ride (May 2026) `WorkoutPatternDetector.detectHeartRateRecovery` reported "4 BPM drop in 60s after peak" while a clear dip of ~40 BPM was visible on the graph during a short stop. Root cause: the detector picks the global peak and measures HR exactly 60s later — on continuous rides the user was already pedalling again at that point, so the dip *within* the window falls outside the measurement point. The metric effectively measures "how fast did your HR go back up after a short dip" instead of "how much did it drop". Moreover, HR recovery is physiologically only interpretable when there is actual rest (cool-down, coffee stop) — not at a random spike in the middle of a continuous effort. The Coach analysis in this case hung a speculative story about fatigue/heat/illness on a non-event.

Solution direction: replace global-peak-+-60s with **pause-based detection**. A pause (power+cadence both ≈ 0 for ≥45s) is the natural window to measure parasympathetic recovery. Thresholds are tied to personal LTHR (a 15% LTHR drop in 60s = excellent) instead of absolute BPM, per the Epic #44 philosophy of personal calibration. With multiple pauses we pin the worst recovery (Management by Exception §1). Good recovery events are not pinned but are injected as context into the coach prompt so the AI can frame positively when explicitly asked.

**Sub-stories:**

* **✅ 47.1 — `PauseDetector` (pure-Swift):** A new `Services/PauseDetector.swift` with a `PauseRecoveryEvent` struct (pause range, hrAtStart, minHRInWindow, drop). Detects contiguous samples where `power < 5 && cadence < 5` (nil if the signal is missing) for ≥45s. Pre-check: the workout must have ≥10 samples with activity (otherwise unusable — think swimming without a cadence sensor). The recovery window per event = `min(60s, pause duration)` — Option A from the design, fair for pauses 45-60s.
* **✅ 47.2 — Rewrite `detectHeartRateRecovery`:** Replaces global-peak-+-60s with iteration over `PauseDetector.detect(in:)` output. Thresholds relative to a `referenceHR` parameter: ≥15% = excellent (no pin), 12-15% = mild, 9-12% = moderate, <9% = significant. Cascading fallback `referenceHR ?? 165`. With multiple pauses, the pause with the lowest ratio wins. The detail text shows the pause duration explicitly ("12 BPM drop in a pause of 1:15").
* **✅ 47.3 — `referenceHR` routing:** `detectAll(in:zones:referenceHR:)` as a new overload; `detectAll(in:profile:)` derives referenceHR via the new helper `referenceHeartRate(from:)` (LTHR preference, otherwise 0.88 × maxHR, otherwise nil). The `zones` parameter stays only for cardiac-drift gating; recovery hangs solely on `referenceHR`.
* **✅ 47.4 — Coach-prompt context (Epic #45 hook):** `WorkoutInsightService.InsightContext` gets a `recoveryEvents: [RecoveryEventSummary]` field. `buildPrompt` adds the line "Recovery context: in a pause of X min HR dropped Y BPM (label)." when events are present — including positive ones. The coach can then frame positively on request ("your autonomic nervous system responded excellently") without the dashboard showing a pin. The caller `WorkoutAnalysisView` calls `PauseDetector.detect(in:)` separately for the InsightContext payload.
* **✅ 47.5 — Tests:** New `PauseDetectorTests` (a 30s traffic-light stop = not detectable, a 90s pause = yes, jitter, samples without a power-stream fallback, a pause near the end of the workout, a swimming fallback where the pre-check fails). `WorkoutPatternDetectorTests`: rewrite the old HR-recovery tests to a pause scenario (a continuous ride without a pause = no pin, a pause with slow recovery = a pin with the correct severity, multiple pauses lowest ratio wins, LTHR/maxHR-fallback/absolute-fallback paths). The existing zone-gate tests are dropped — replaced by referenceHR equivalents.
* **✅ 47.6 — Doc updates:** an `ARCHITECTURE.md` section "HR recovery via pause detection" with the why-reasoning (post-effort vagal recovery requires a rest window, otherwise you measure something other than you think). ROADMAP status from 🔄 → ✅ on merge.

**Tradeoff:** workouts without a pause (interval tests, short tempo loops) no longer get an HR-recovery pin — correct behaviour, because without a rest window you cannot measure recovery. The cardiac-drift detector catches fatigue signals that manifest otherwise (HR rise between halves at equal intensity), so we lose no detection layer.

**Status:** ✅ — implemented on `feature/epic-47-pause-based-hr-recovery`. All 730 unit tests green, including 13 new `PauseDetectorTests` and rewritten HR-recovery scenarios. Awaiting on-device validation + merge.

---

### ✅ Epic #48: Coach analysis couples to goals + periodisation

Trigger: after Epic #47 the Coach-analysis tile always shows a short execution confirmation — also on rides without patterns (positive framing). But the text is detached from the broader context: *why* did you do this ride? Does it fit your Build phase for the marathon? Does it tick off a long-run milestone? On the Dashboard the chat coach already has access to goal status (`BlueprintContextFormatter`) and periodisation (`PeriodizationResult.coachingContext`) via `ChatViewModel.cacheActiveBlueprints` / `cachePeriodizationStatus`. We want to pass that same infrastructure per workout to the `WorkoutInsightService` so the Coach analysis explicitly bridges to the goal.

**Sub-stories:**

* **✅ 48.1 — Extend `InsightContext`:** Two optional fields on `WorkoutInsightService.InsightContext`: `goalsContext: String?` (output of `BlueprintContextFormatter.format(results:)`) and `periodizationContext: String?` (joined `PeriodizationResult.coachingContext` blocks). With no active goal or no blueprint the field stays nil and the block in the prompt falls away.
* **✅ 48.2 — `WorkoutAnalysisView` builds the context:** `@Query` for `FitnessGoal` (active filter), `ActivityRecord`, `DailyReadiness` (latest). Call `BlueprintChecker.checkAllGoals(goals, activities:)` and `PeriodizationEngine.evaluateAllGoals(goals, activities:, latestReadinessScore:)`, format with the existing helpers and pass the strings to `InsightContext`. Reuses exactly the same infrastructure the chat coach uses — no duplicate format logic.
* **✅ 48.3 — `buildPrompt` + system instruction:** Two new blocks in the prompt: `[DOELEN-STATUS]` and `[PERIODISERING]`, only when the strings are non-empty. The system instruction gets rule 5: "Connect the execution explicitly to the goal and the current phase when present — e.g. 'fits your Build phase for the marathon, and this 32km approaches your 28km long-run milestone'. No active goal = don't mention." The style clause stays 3 sentences max; the coach picks the most relevant connection.
* **✅ 48.4 — Extend the cache key with a goals fingerprint:** The current cache key is `pattern-fingerprint + profile-fingerprint`. Add: `goals-fingerprint` (a hash of active goal IDs + milestone status + periodisation phase per goal) so a new goal status (milestone reached, phase transition) automatically triggers a new Coach analysis instead of serving a stale framing from the cache.
* **✅ 48.5 — Tests + docs:** New `WorkoutInsightServiceTests` for the extended prompt building (confirms that `[DOELEN-STATUS]` + `[PERIODISERING]` are sent when available, and omitted on nil). ARCHITECTURE.md §10 (Workout Pattern Detection) gets a short update about the extended insight context.

**Tradeoff:** more tokens per AI call → slightly higher API cost. For power users who actively train goal-directed, the gain (more specific, goal-aware framings instead of loose ride observations) far outweighs the cost. Workouts without an active goal or without a blueprint automatically fall back to the pre-Epic-#48 behaviour.

**Status:** ✅ — merged via PR #258. Validated on-device: the coach now makes one concrete connection with the active phase/milestone instead of a loose ride observation.

---

### ✅ Epic #49: HK weather metadata in the Coach analysis

Trigger: on a threshold session or a warm ride the coach often asks about heat as an explanation for drift/decoupling — while HealthKit already stores the actual temperature and humidity during the workout in `HKMetadataKeyWeatherTemperature` / `HKMetadataKeyWeatherHumidity` whenever the iPhone was present. Goal: read that metadata and pass it to the coach prompt, so the coach can weigh heat/humidity instead of asking about it.

**Sub-stories:**

* **✅ 49.1 — Extend `ActivityRecord`:** Two optional fields — `temperatureCelsius: Double?` and `humidityPercent: Double?`. A pure addition, so no schema-version bump needed (SwiftData lightweight migration).
* **✅ 49.2 — HK ingest path:** A new `HealthKitSyncService.extractWeather(from:)` static helper reads `HKMetadataKeyWeatherTemperature` (Apple uses degF; convert explicitly to Celsius) and `HKMetadataKeyWeatherHumidity` (can be 0-1 or 0-100; normalise to 0-100). Defensive against wrong-type values and missing keys → nil without a crash.
* **✅ 49.3 — Coach prompt:** `WorkoutInsightService.InsightContext` gets `temperatureCelsius` + `humidityPercent`. `buildPrompt` adds a `[WEER TIJDENS WORKOUT]` block when at least one field is filled. The system instruction gets a rule: "weigh a temperature >25°C or humidity >70% explicitly as an explanation for drift/decoupling — don't ask about it anymore". No block = fall back to generic assumptions.
* **✅ 49.4 — Cache key:** The `WorkoutAnalysisView` cache fingerprint gets a `weatherFingerprint` so a DeepSync or a later ingest update regenerates the Coach analysis with the updated heat context.
* **✅ 49.5 — Tests + docs:** `HealthKitWeatherExtractionTests` (9 tests) guarantees the unit conversion + edge cases (missing/empty/wrong-type). ARCHITECTURE.md §10 update about the weather context.

**Tradeoff:** only workouts where the iPhone was present have metadata. Strava-only rides and old HK records without weather stay without context — the coach falls back to generic assumptions there. If a need shows, a later Epic with GPS + a historical weather API as fallback follows.

**Status:** ✅ — merged via PR #260. 743 unit tests green; validated on-device.

---

### ✅ Epic #50: Open-Meteo historical weather for Garmin/bike-computer-only rides

A follow-up to Epic #49 (HK weather metadata). Garmin/bike-computer-only cycling sessions have no iPhone counterpart in HK, so `HKMetadataKeyWeather*` is missing and the cross-source merge from #49 yields nothing. With Strava's `start_latlng` + `startDate` we can query Open-Meteo's archive API for historical temperature/humidity at that specific location and time.

**Sub-stories:**

* **✅ 50.1 — Extend the Strava DTO:** `start_latlng: [Double]?` added to `StravaActivity`. Strava delivers it as a `[lat, lng]` array; an empty array (indoor/manual) is normalised to nil for a coherent "no location" signal.
* **✅ 50.2 — `HistoricalWeatherService`:** Pure-Swift with an injected `WeatherURLFetcher` (testable without a real HTTP call). Builds the URL for the archive API (>5 days old) or the forecast API with `past_days` (more recent). Privacy: GPS coords rounded to 0.1° (~11km) before the API call. Hour-bucket extraction matches the hour closest to the workout start date. Fails gracefully — on a network/API error the caller gets `(nil, nil)`.
* **✅ 50.3 — Strava ingest integration:** A new `enrichRecord(_:from:startDate:)` extension on the service. Called in `AppTabHostView.performAutoSync` (auto-sync, max 14 calls) and `SettingsView.runStravaHistoricalSync` (the 1-year button, ~50-100 calls). Idempotent — skips if the record already has weather data (e.g. via the Epic #49 cross-source merge). Combines with Epic #49: the existing HK cross-source merge wins where possible; Open-Meteo fills in the rest.
* **✅ 50.4 — Tests:** `HistoricalWeatherServiceTests` (11 tests): privacy rounding, archive-vs-forecast URL choice, hour-bucket matching, graceful handling of Open-Meteo `null` values, error paths (invalid coords, out-of-range date, non-2xx response), end-to-end with a mock fetcher.

**Privacy consideration:** Open-Meteo logs no request IPs and is open-source, but we still send GPS coords there. By rounding to 0.1° (~11km radius) we leak no exact location — for weather classification that is plenty (the temperature gradient over 11km is usually <1°C).

**Tradeoff:** ~10s extra on the "Sync historical data" button for 100 rides (sequential). Auto-sync impact negligible (max 14 calls per run). The Open-Meteo free tier covers 1000 calls/day — well within budget for one user.

**Status:** ✅ — merged via PR #261 (+ fix PR #262: the `.skippedSameSource` path also does the weather merge). 769 unit tests green; validated on-device.

---

### ✅ Epic #51: Error messages, validation & visibility (user-feedback hardening)

Trigger: a systematic analysis from the user's perspective (three parallel audits on coach chat, settings/forms and the data layer → UI error propagation) exposed a series of unhappy flows where the app gives silent errors, missing validation or confusing feedback. Not broken — but in conflict with the Management-by-Exception principle. Full scope + acceptance criteria per sub-story in [issue #265](https://github.com/markclausing/vibecoach/issues/265).

**Functional grouping** (each its own PR):

* **✅ 51.A — Coach conversation:**
  - **✅ A1 + A5:** `ChatScopeInstruction` pastes an explicit scope restriction at the top of the system prompt (the coach refuses off-topic questions with a fixed framing); `ChatErrorMessageMapper` (pure-Swift) replaces the generic "temporary problem" message with specific texts per error category — offline / timeout / DNS / cancelled / safety-block / invalid-key / overloaded / generic. 17 unit tests. Merged via PR #269.
  - **✅ A2 + A3 + A4 + A6 (PR #270):** `ChatModelSwitchNotice` shows a banner at the top of the chat as soon as the user switches Gemini model in Settings during `isTyping` (the current answer still comes from the previous model, the next question uses the new one — the `_modelBuiltForName` cache handles an automatic rebuild without the user having to log in again). `ChatConversationTrimmer` (generic, pure-Swift) splits long conversations into a collapsed archive (>50 messages) + a visible tail — a UI-only optimisation because the chat API does not send message history. `ChatInputValidator` clamps paste actions to 5000 characters with a counter from 80% and a one-off toast on truncation — preventing 45s timeouts on large text blocks. Request cancel via a `currentRequestTask` handle in `ChatViewModel` + `cancelOngoingRequest()` on `ChatView.onDisappear` — a `CancellationError` causes no error bubble or banner, only an `isTyping = false`. 28 unit tests across the three helpers.

  *The provider switch was specified more broadly in the issue (Gemini ↔ OpenAI ↔ Anthropic) — in this codebase the app stays Gemini-only, so A2 implements the model switch (primary ↔ fallback Gemini model) and not a cross-provider switch. Cross-provider would warrant its own Epic.*
* **→ 51.B — moved to Epic #62 (story 62.1).** Create & manage goals: a date at least +7 days, realistic stretch times per sport, a title trim, a soft-delete against stale coach context.
* **✅ 51.C — Profile & training thresholds:** `PhysiologicalThresholdValidator` (pure-Swift, AppStorage-free) does live range checks + cross-validation (Max HR > Rest HR, LTHR < Max HR, LTHR > Rest HR). `ThresholdEditSheet` shows inline warnings/errors and disables Save on physiologically inconsistent combinations. A round-trip check on `applyManualEdit` detects storage failures. The `zonePreviewCard` shows a context-aware explanation of why HR/power zones are missing (which field is still required, or which cross-error blocks the calculation) instead of a generic "set thresholds" text. 17 unit tests. Merged via PR #268.
* **→ 51.D — moved to Epic #62 (story 62.2).** AI provider & API key: auto-trim on paste, prefix detection for the wrong provider, persistent test feedback.
* **→ 51.E — moved to Epic #62 (story 62.3).** Onboarding & permissions: HealthKit as required, notifications as optional, a status banner on skip, after-the-fact-revoke detection, a status overview in Settings.
* **✅ 51.F — Data sync:**
  - **✅ F1 + F2 + F5 (PR #272):** `SyncStatusStore` tracks the last success timestamp and the last error category per data source; `SyncBannerStateBuilder` (pure-Swift) determines from a snapshot which banner is shown — priority offline > rate-limited > error > nil so one central `SyncStatusBanner` on the Dashboard renders all three messages consistently. F2: `FitnessDataError.rateLimited(retryAfter:)` + `StravaRateLimitParser` extracts the `Retry-After` time (delta-seconds and HTTP date, fallback 15 min) and `StravaRateLimitStore` persists the cooldown across app launches so a retry storm right after launch becomes impossible. F5: `NetworkReachabilityMonitor` (an NWPathMonitor wrapper, singleton) sets the offline state. `.missingToken` is deliberately filtered out — users without a Strava coupling get no banner. 24 unit tests (11 parser + 13 banner-builder) + 4 new FitnessDataService 429 tests.
  - **→ F3 + F4 + F6 — moved to Epic #62 (story 62.4):** HK per-type permission, a non-blocking weather error with a retry marker, captive-portal detection.
* **→ 51.G — moved to Epic #62 (story 62.5).** Proactive coach (background): a status row in Settings, a notification-permission pre-check, a visible registration error.
* **✅ 51.H — App updates & data safety:** `MigrationFallbackStore` + a Dashboard `MigrationFallbackBanner` closes the half implementation from CLAUDE.md §12 (the `vibecoach_migrationFallbackAt` flag is now actually shown to the user); `AppVersionInfo` renders the marketing version + build number at the bottom of Settings. 11 unit tests (5 store + 6 version-info). Merged via PR #267.

**Status:** ✅ — delivered stories (A, C, F1/F2/F5, H) merged via PR #267/#268/#269/#270/#272. The remaining open hardening groups (B, D, E, F3/F4/F6, G) have not lapsed but are brought together under **Epic #62** so they stay visible as one forward-looking goal.

---

### ✅ Epic #52: Sharpen workout analysis (weather + prompt + cadence)

Trigger: user feedback on a 90-minute run on 24 May 2026. Three deviations from the expected behaviour of the workout-detail coach:
1. **The weather snapshot mismatches reality.** HK metadata logs one temperature at ride start (15°C at 9:43); during the run it rose to ~22°C. The Coach only saw that 15°C and could not weigh the heat.
2. **The prompt ends with a question.** The analysis on `WorkoutAnalysisView` has no chat function, so every open question to the user is left hanging.
3. **No cadence chart for running.** Cycling shows cadence via `cyclingCadence`; running has no native HK identifier and stayed empty, while Strava streams already deliver cadence themselves.

**Sub-stories** (one Epic PR per the multi-story workflow):

* **✅ 52.1 — Hourly weather aggregate over the workout window:** `HistoricalWeatherService.fetchWeatherRange(latitude:longitude:startDate:endDate:)` fetches all hourly Open-Meteo values within `[start, end]` and aggregates to peak + avg for temperature and humidity (the pure helper `extractWindowAggregates` — 4 unit tests). `WorkoutInsightService.InsightContext` gets 4 new range fields; `buildPrompt` shows a `[WEER TIJDENS WORKOUT — range]` block when present, otherwise the existing snapshot block. The system-instruction paragraph updated: the peak temperature is the lower bound for heat-stress evaluation. Schema V3 → V4 (lightweight migration) adds `startLatitude` + `startLongitude` to `ActivityRecord`; `enrichRecord` persists those at every Strava ingest so the Coach call can fetch the range afterwards without querying the Strava API again. SchemaV3 gets its own `ActivityRecord` snapshot (the May-2026-incident safety net per CLAUDE.md §2.1). 4 unit tests of the V3→V4 migration (FitnessGoal + UserPreference survive, coords writable after migration).
* **✅ 52.2 — Stricter coach prompt: no more questions:** the system instruction adjusted in several places — "End with an open question" and "ask a calibration question" replaced by observation statements. A new top-level rule: "This analysis appears on a detail view without a chat function. **Never** ask the user a question." A closer at the bottom: "Never end with a question mark." No code safety net (only a prompt instruction) — if Gemini in a rare exception still generates a question, that stands out during on-device validation.
* **✅ 52.3 — Running cadence chart + Coach context:** `WorkoutSampleService.fetchRunningStepCadence` aggregates HK `stepCount` via `HKStatisticsCollectionQuery` over 5s buckets and converts to steps-per-minute. The Strava cadence stream stays the fallback (already supported by the existing ingest). A new `cadenceChart` in `WorkoutAnalysisView` for running workouts (LineMark + scrubber, no normative zone bands). `WorkoutInsightService.InsightContext` gets `averageCadenceSPM` + `peakCadenceSPM`; the system-instruction paragraph for cadence with thresholds (160 / 180 spm, peak-vs-avg > 20 spm) and the rule that cadence is only touched on a related pattern. The cache fingerprint extended with cadence so new samples trigger a fresh analysis. The scrubber card ("details at the time point") shows the spm at the scrubbed position.

**Post-merge fixes (after on-device validation):**
* **One-shot re-ingest on an ingest-revision bump:** `DeepSyncService` keeps a processed-UUID set to avoid double fetching. Existing HK running workouts were in it → the new stepCount cadence was never fetched for them. `currentIngestRevision = 2` triggers a one-off re-ingest on launch (clearing the processed set) so all workouts in the 30-day window get the richer sample set again.
* **Cross-source cadence (Strava dedup winner):** an Apple Watch run often also comes in as a Strava activity; on dedup the Strava record wins (`device_watts` → +500 in `ActivityDeduplicator.score`) and the view requests samples under the Strava UUID, while the Watch `stepCount` lives under the HK UUID. `WorkoutSampleService.fetchStepCadence(start:end:)` decoupled from `HKWorkout` so a time-window query (HealthKit deduplicates stepCount itself across sources) still finds the cadence. `WorkoutAnalysisView` falls back to this (`loadCadenceFallbackIfNeeded`) when the stored samples contain no cadence; the chart + Coach prompt + scrubber use a unified `cadencePoints` source.

**Effort realised:** ~750 LOC across `Models/`, `Services/`, `Views/` + 13 new unit tests (7 weather-range + 4 schema-migration + 2 ingest-revision).

**Status:** ✅ — merged on `main` via PR #275 (squash). Validated on-device: weather range, the no-questions prompt and the cadence chart (incl. cross-source HK fallback) work.

---

### ✅ Epic #53: Multi-Provider BYOK — OpenAI, Claude & Mistral

Trigger: since Epic #20 (Sprint 20.1) the `AIProvider` enum (`gemini` / `openAI` / `anthropic`) has existed in the UI, but `AIProvider.isSupported` returns **true only for `.gemini`** — the other choices are dead options. The whole inference layer is Gemini-only: the "abstraction" `GenerativeModelProtocol` leaks the Google SDK type `ModelContent.Part`, and `UserAPIKeyStore` stores exactly one key under `VibeCoach_UserAIKey`. Goal of this Epic: make the three remaining providers (OpenAI, Anthropic Claude, **Mistral** — to be newly added to the enum) fully work as a BYOK choice, including onboarding, Settings, model selection, validation and a test suite. The user brings their own key; calls go directly from device to provider (no proxy in the inference path, per the existing BYOK philosophy — see [ARCHITECTURE.md §3](ARCHITECTURE.md)).

**Architecture principles (to confirm before implementation):**

1. **A provider-neutral abstraction instead of an SDK leak.** `GenerativeModelProtocol.generateContent(_ parts: [ModelContent.Part])` now hangs directly off `GoogleGenerativeAI`. That type must be replaced by our own value type (e.g. `AIPromptPart` with `.text` / `.imageData` cases) so the protocol layer becomes SDK-free. Touches: `RealGenerativeModel`, `ChatViewModel.buildGenerativeModel` (now builds `[ModelContent.Part]`), `WorkoutInsightService`, `MockGenerativeModel`, `UITestMockGenerativeModel`.
2. **Light REST clients instead of three extra SDKs.** The app only needs one call pattern: single-shot prompt → text/JSON response. OpenAI (`/v1/chat/completions`), Anthropic (`/v1/messages`) and Mistral (`/v1/chat/completions`) can be served with a thin `URLSession` client. That keeps the SPM footprint small (only `GoogleGenerativeAI` stays a dep) and avoids SDK-version drift. Document the decision per provider in `ARCHITECTURE.md`.
3. **Per-provider differences the adapter must absorb:**
   - **System instruction:** Gemini `systemInstruction`, OpenAI/Mistral a `role: "system"` message, Anthropic a top-level `system` parameter.
   - **JSON output:** Gemini `responseMIMEType: "application/json"`, OpenAI/Mistral `response_format: {type: "json_object"}`, Anthropic has no native JSON mode → prompt-driven + possibly assistant prefill. The existing `extractCleanJSON` helper stays the safety net.
   - **Auth & rate-limit errors:** each provider has its own HTTP codes/error bodies. Map to a uniform `AIProviderError` so the existing 503/429 waterfall (primary → fallback) and the auth-error detection in `ChatViewModel` stay provider-agnostic.
4. **Per-provider key storage.** `UserAPIKeyStore` stores one key; on a provider switch the other key would be lost. Migrate to keyed storage (`VibeCoach_UserAIKey_<provider>`) with a one-off migration of the existing key to the `gemini` slot (idempotent, per the existing `migrateFromUserDefaultsIfNeeded` approach).

**Sub-stories:**

* **✅ 53.1 — Provider-neutral abstraction layer + factory:** `GenerativeModelProtocol` detached from `GoogleGenerativeAI` — a new SDK-free `AIPromptPart` type (`.text` / `.imageData`) + an `AIProviderError` enum + a `RealAIProviderClient` marker in `GenerativeModelProtocol.swift`. The new `AIModelFactory.makeModel(provider:modelName:systemInstruction:jsonMode:timeout:apiKey:session:)` routes per `AIProvider` to the right client; `RealGenerativeModel` (the Gemini adapter) moved into the factory. `ChatViewModel.buildGenerativeModel`, `WorkoutInsightService.makeModel` and `AddGoalView.fetchAITargetTRIMP` now route via the factory. Overload detection unified via `AIProviderError.isOverload(_:)` (recognises Gemini `internalError` and our own `.overloaded`).
* **✅ 53.2 — REST clients for OpenAI, Claude & Mistral:** `OpenAICompatibleModelClient` (serves OpenAI + Mistral via `/v1/chat/completions` with `Authorization: Bearer`; one shared client instead of two near-identical types — DRY) and `AnthropicModelClient` (`/v1/messages`, `x-api-key` + `anthropic-version`, JSON via assistant prefill `{`). System-instruction placement and JSON mode per provider, base64 vision parts, error mapping to `AIProviderError` via `AIProviderHTTP.validate` (429/503/529 → `.overloaded`, 401/403 → `.authenticationFailed`). Transport errors bubble through as `URLError` to the existing mapper. Timeout via `URLRequest.timeoutInterval`. 16 unit tests in `AIModelClientTests` (URLProtocol mock, no live calls). **The Mistral enum case** (`AIProvider.mistral`) pulled forward from 53.3 so the factory switch is complete; key-storage-per-provider + UI stay in 53.3/53.6.
* **✅ 53.3 — Per-provider key storage + `isSupported`:** `UserAPIKeyStore` now has per-provider slots (`serviceName(for:)` → `VibeCoach_UserAIKey_<raw>`) with `read/write/delete(for:)` + DI variants. A one-off `migrateToPerProviderKeysIfNeeded` moves the legacy single key to the Gemini slot (idempotent, runs in `AIFitnessCoachApp.init()` after the UserDefaults→Keychain migration). `AIProvider.isSupported` → `true` for all four; a new `AIProvider.current(in:)` + `appStorageKey` as the central provider source. ChatViewModel/WorkoutInsightService/AddGoalView/Settings read/write the slot of the **active** provider; Settings reloads the key + resets the test status on a provider switch. The UI-test reset clears all provider slots.
* **✅ 53.4 — Model selection per provider:** `AIModelCatalog.builtIn(for:)` delivers a curated static catalogue per provider (Gemini = the existing Worker catalogue). Defaults: OpenAI `gpt-4.1` + `gpt-4.1-mini`, Claude `claude-sonnet-4-6` + `claude-haiku-4-5`, Mistral `mistral-large-latest` + `mistral-small-latest`. `AIModelAppStorageKey` is provider-aware (`primaryKey(for:)`/`resolvedPrimary(for:)` etc.); Gemini keeps the legacy Epic #35 keys (backward-compat). ChatViewModel resolves primary/fallback/snapshot/banner consistently via `currentProvider` (preventing a rebuild loop). The provider-specific model *pickers* in Settings stay 53.6; until then, non-Gemini providers use their default model.
* **✅ 53.5 — Multi-provider key validation:** `APIKeyValidator.validate(_:provider:)` pings the cheapest model per provider via the factory; `classify(_:)` generalises to `AIProviderError` (auth → invalidKey, overloaded → rateLimited). `validateGeminiKey` stays as a back-compat alias. The "Test key" button in Settings now works for every provider. `AIProviderHTTP.validate` includes the (truncated) provider error body in `AIProviderError.http(status:message:)` so a 4xx shows the real reason (e.g. a deprecated model) instead of a bare status code.
* **✅ 53.6 — Settings UI extension:** `AIProviderSettingsView` shows a provider picker with all four options; per selected provider the right `keyPlaceholder`, `getKeyURL` link, key field (from the per-provider Keychain slot) and model picker. Gemini = the live Worker catalogue (Epic #35); OpenAI/Claude/Mistral = the static `AIModelCatalog.builtIn(for:)` with `@State`-bound pickers (`PrimaryProviderModelPicker`/`FallbackProviderModelPicker`) that persist provider-separated to the `AIModelAppStorageKey` keys. The "Test key" feedback and `aiCoachConnectionSubtitle` (Epic #43) show the active provider via `AIProvider.shortName`.
* **✅ 53.7 — Onboarding flow:** the step "Your AI" (`OnboardingView` + `AIProviderPrivacyContent`) now shows all four providers (segmented, via `shortName`) + a `getKeyURL` link for the chosen provider. Key entry stays deferred to Settings; "Skip, do it later" + the `NoAPIKeyView` empty state work unchanged for every provider.
* **✅ 53.8 — Call-site cleanup:** `AddGoalView.fetchAITargetTRIMP()` refactored to the factory (now follows the Epic #35 model choice instead of a hardcoded `gemini-flash-latest`), `print` debug aids removed. `import GoogleGenerativeAI` removed from `ChatViewModel`, `WorkoutInsightService`, `AddGoalView` and `UITestMockEnvironment` + the unit-test `MockGenerativeModel`. After this sprint only the `AIModelFactory` (the Gemini adapter) and `APIKeyValidator` (follows in 53.5) import the SDK. `ChatErrorMessageMapper` + `WorkoutInsightService.mapError` now also recognise `AIProviderError`.
* **✅ 53.9 — Test suite + docs:** mocks adapted to the SDK-free signature (sprint A); per-client `URLProtocol` tests, per-provider validator tests, a keyed key-store migration test (sprint A+B); an `AIProvider.shortName` test + a provider-switch UI test (`testSwitchingToMistral_ShowsProviderModelPicker`) in `AIModelPickerUITests`. `ARCHITECTURE.md §3` describes the whole abstraction + per-provider differences; `architecture.json`/`.html` synced (`AIModelFactory` module, `docRevision` bumped) per [CLAUDE.md §7](../CLAUDE.md#architectuur-visualisatie-afgeleide-artefacten).

**Open points / risks:**

- **Anthropic JSON reliability:** without a native JSON mode, prompt-driven JSON is more fragile. The `SuggestedTrainingPlan` decode + `extractCleanJSON` must catch this; possibly deploy assistant prefill (`{`). Validate on-device with a real plan-generating conversation.
- **The cost/latency profile differs per provider** — the 45s timeout and the 503/429 waterfall are tuned to Gemini; verify per provider that the fallback behaviour is sensible.
- **The system instruction is ~274 lines of NL** (see Epic #37.2). That prompt is tuned to Gemini; tone differences between providers only manifest in production (subjective). On-device A/B per provider recommended before claiming "supported".
- **Scope boundary:** no streaming, no multimodal input beyond the existing text+image parts, no provider-specific safety settings (all providers on defaults, just like now with Gemini).

**Effort estimate:** ~3 PRs. (A) 53.1 + 53.2 + 53.8 — abstraction + clients + call-site cleanup (core, ~the largest post). (B) 53.3 + 53.4 + 53.5 — key storage + model catalogue + validation. (C) 53.6 + 53.7 + 53.9 — UI + onboarding + tests + docs. Roughly ~30–40h depending on how much per-provider tuning the prompt requires.

**Status:** ✅ — completed in three sprints (PR #276 sprint A, PR #277 sprint B, sprint C on `feature/epic-53-byok-ui-onboarding`). Gemini/OpenAI/Claude/Mistral are all four fully-fledged BYOK choices: per-provider Keychain slots, per-provider model pickers (Gemini a live Worker catalogue, the others static), per-provider validation and a provider-aware onboarding step. Validated on-device by the user: the Mistral coach works end-to-end, the Claude key is accepted (only a credit balance was missing), error messages show the real provider reason. Existing Gemini users unchanged (legacy key migrated, model choice + AppStorage keys preserved). 912 unit tests + UI tests green.

---

### ✅ Epic #54: Dynamic model catalogue per provider

Trigger: after Epic #53 the model picker per non-Gemini provider chose from a **static** `AIModelCatalog.builtIn(for:)` list. That ages quickly — a user saw gpt-5.4 / gpt-5.5-pro in his OpenAI account while the app showed `gpt-4.1` as the newest. Goal: fetch the model list per provider live, just as Gemini does via the Cloudflare Worker.

**Approach:** each provider has a `/v1/models` endpoint that we call **directly from the device with the BYOK key** — the key does not leave the device via our servers (like the chat calls), so no privacy regression and the list is user-specific. Gemini deliberately stays on the Worker (a global, validated list with our own key); for OpenAI/Anthropic/Mistral the Worker route would have to forward the user key, which we don't want.

* **✅ 54.1 — `ProviderModelListService`:** fetches `/v1/models` per provider (OpenAI `Authorization: Bearer`, Anthropic `x-api-key` + `anthropic-version`, Mistral `Bearer`), parses the shared `{ data: [...] }` shape and **filters to chat models**: Anthropic = all (only `claude-*`), Mistral = `capabilities.completion_chat`, OpenAI = a heuristic on id (`gpt-`/`chatgpt-`/`o1`/`o3`/`o4`, excluding embedding/audio/realtime/transcribe/tts/image/whisper/etc.). Sorted descending (newest on top). Falls back via the caller to `AIModelCatalog.builtIn(for:)` on error/empty key. Lives in `AIModelFactory.swift` (the client subsystem). 7 unit tests (URLProtocol mock, no live calls).
* **✅ 54.2 — Settings wiring:** `AIProviderSettingsView` shows the live list for non-Gemini providers — starts with the static list (the picker is never empty), replaces it once the fetch succeeds, and resets a stored choice that is no longer in the live list (a deprecated model). Refreshes on `onAppear`, on a provider switch and after a successful key test. The footer shows the load/source status. Gemini keeps the Worker catalogue.

**Open points:** no persistent cache (a fetch per Settings open, like Gemini's Worker route); the OpenAI chat filter is heuristic (a future non-chat `gpt-*` model could slip through — then the coach-call error body catches it). Possible follow-up: caching with a TTL + a manual "refresh models" button.

**Status:** ✅ — validated on-device: all four providers load their live model list once a key is entered. One UX refinement during validation: without an entered key the fetch silently skipped (no error → looked broken); the footer now explicitly asks for the key to be entered + tested, and on a real fetch error shows the reason (e.g. 401/403 if the key has no *Models* read right). 919 unit tests green. PR #279.

---

### ✅ Epic #58: README as showcase — user-focused product page

The `README.md` was **developer-focused** (status, tech stack, setup); a new visitor got no sense of *what the app does for them* or *what it looks like*. The README was rewritten into a real product page: a hero + eight feature blocks (screenshot + sober description + a "what you get" benefit) at the top, then a concise technical summary ("Under the hood") with cross-references instead of duplication, and finally a complete "Build & run it yourself" section.

**Agreed (June 2026):** a full showcase **in the README itself** (not as a separate page) → §7 adjusted so only the technical-summary block must stay < 1 screen, the showcase may be longer. Screenshots as **placeholders** in `docs/screenshots/` (fixed filenames, the maintainer swaps real captures later). Tone **sober/factual**, text in **English** (consistent with the §7/§10 docs convention).

* **✅ Story 58.1 — Showcase restructuring.** README rewritten: a hero (`00-hero.png`) + "Why VibeCoach" + eight feature blocks with left/right-aligned screenshots (Vibe Score, proactive coaching, AI coach BYOK, workout deep-dive, goal phases, multi-day events + per-stage weather, dual-source sync, language & privacy). Then "Under the hood" (a stack table + principles + CI + recently-completed + cross-references to ARCHITECTURE/ROADMAP/CLAUDE/architecture.html) and "Build & run it yourself" (requirements, `Secrets.swift`, the BYOK key in Settings, the optional Strava proxy, build & run, running tests). The simulator push test now sits in a collapsed "Developer notes".
* **✅ Story 58.2 — Screenshot infrastructure.** `docs/screenshots/` with nine placeholder PNGs (320×690, stdlib-generated) + a `README.md` that explains per slot which capture belongs to it, the format (PNG portrait, EN, demo data), and how to swap them without touching the main README.
* **✅ Story 58.3 — Update doc discipline.** `CLAUDE.md` §7: the README scope rule reconciled with the showcase (the showcase may be long, the technical summary < 1 screen) + the README update protocol now refers to "feature block + screenshot slot" for significant features.

**Decisions on the open points:** (a) screenshots live in the repo (`docs/screenshots/`, small placeholders for now); (b) an **EN-only** set of "hero" screens instead of per-language — less maintenance burden; (c) tone **sober**, no marketing superlatives; (d) §7 adjusted instead of splitting off the showcase — everything in the README, only the technical block short.

**PR #315. Effort:** ~2–3h. **Out of scope:** taking real screenshots (requires on-device captures by the maintainer), per-language screenshot sets, external image hosting, badges/shields.

---

### ✅ Epic #60: Per-phase milestone insight in the Goals view (collapsible)

Worked out technically and built (merged via PR #313). The user wants to see more concretely **what to hit and when** per training phase: on what date which milestone/target. The Goals view now shows the phases as a compact bar + a timeline with four hardcoded transition points, but no per-phase targets and no expansion. Goal: show per phase (Base/Build/Peak/Taper) a date range + targets + key trainings + status, in a **`DisclosureGroup` per phase** (closed = phase name + date range + status indicator; open = targets, target dates, progress, essential workouts).

#### Current state in the code (grounding)

- **Phase definition** — `TrainingPhase` (`Models/TrainingPhase.swift`): four cases, each with a `multiplier` (1.00/1.15/1.30/0.60), `successCriteria` → `PhaseSuccessCriteria` (`longestSessionPct`, `weeklyTrimpPct`, `sessionWindowWeeks`). `TrainingPhase.calculate(weeksRemaining:)` (r65-72) determines the phase via fixed week boundaries (<2 taper, 2–4 peak, 4–12 build, ≥12 base).
- **Phase dates + progress (current phase only)** — `ProgressService` (`Services/ProgressService.swift`): `BlueprintGap` (r82-243) holds `currentPhase` + `phaseStartDate/EndDate` + cumulative TRIMP/km (required/actual, linearly interpolated). `phaseDateRange(phase:targetDate:goalCreatedAt:)` (r346-374, **private**) computes a [start,end] per phase with **fixed offsets** (-12/-4/-2 weeks relative to `targetDate`). `analyzeGap` (r259-338) builds this only for the **current** phase and only when there is a blueprint.
- **Milestones (deadline-based, not phase-coupled)** — `BlueprintChecker.check(goal:activities:)` (`Services/BlueprintChecker.swift` r118-151) → `[MilestoneStatus]` with `deadline` (= `targetDate − mustCompleteByWeeksBefore`), `isSatisfied`, `satisfiedByDate`. Source: `GoalBlueprint.essentialWorkouts` (`Models/GoalBlueprint.swift`).
- **View** — `GoalsListView.swift`: `phaseSegments(for:)` (r539-552) renders the bar with a **week budget** (taper 2 / peak 2 / build ≤8 / base = rest), `milestonesForGoal(_:)` (r577-597) makes 4 hardcoded `GoalMilestoneItem`s, rendered by `MilestoneTimelineRow` (r630-674). `PhaseProgressCard` (r676+) shows progress bars. **`DisclosureGroup` is used nowhere in the codebase** — this becomes the first.

#### ⚠️ Most important technical finding: two diverging phase models

The **bar** (`phaseSegments`, a week budget from `goal.totalDays`) and the **service** (`phaseDateRange`, fixed −12/−4/−2 offsets) use **different** phase windows. For a goal >16 weeks they roughly coincide, but for a **short goal** (e.g. 8 weeks) they diverge: `phaseDateRange` then puts "base" before `createdAt` (clamped) while `phaseSegments` compresses base/build. A per-phase expansion that sits next to the bar must show the same dates → **one shared source of truth for phase windows is a hard requirement** of this Epic, otherwise the bar and the list contradict each other.

#### Proposed architecture

**Data layer (computed, no schema migration — §2.1).** New pure value types (AppStorage-free, §6):
- `PhaseSummary`: `phase: TrainingPhase`, `dateRange: ClosedRange<Date>`, `weekCount: Int`, `status: PhaseStatus` (`.past`/`.current`/`.future`), `targets: [PhaseTarget]`, `milestones: [PhaseMilestone]`.
- `PhaseTarget`: `label`, `current: Double?`, `required: Double`, `unit`, `isInverted: Bool` (taper: lower = better, reusing `MilestoneItem.isInverted` logic), `progress`.
- `PhaseMilestone`: derived from `MilestoneStatus` — `description`, `targetDate`, `isSatisfied`, `satisfiedByDate`.
- `PhaseTimeline`: `[PhaseSummary]` for one goal.

**Service layer.** `ProgressService.phaseTimeline(for goal:activities:) -> PhaseTimeline`:
1. **Unify the phase window**: extract the week-budget logic from `phaseSegments` into a shared helper (e.g. `PhaseWindowCalculator`) that feeds both the bar and the timeline; make `phaseDateRange` part of it or replace it. This resolves the divergence above.
2. Per phase: a date range + `weekCount`; `status` via comparison with `Date()`; targets via `PhaseSuccessCriteria` (`longestSessionPct × blueprint.minLongRunDistance`, `weeklyTrimpPct × blueprint.weeklyTrimpTarget`) + cumulative TRIMP/km (reusing the interpolation from `analyzeGap` — extract to a helper so the current phase and the timeline give the same figures).
3. **Bucket the milestones**: place the `MilestoneStatus`es from `BlueprintChecker.check(...)` in the right `PhaseSummary` based on which phase window their `deadline` falls in.
4. **Progress only where meaningful**: `.past`/`.current` show actual vs. required; `.future` shows only targets (no "0% achieved" noise).

**View layer.** A new component `PhaseMilestonesView(timeline:)`:
- A `DisclosureGroup` per `PhaseSummary`, `@State private var expandedPhases: Set<TrainingPhase>` with the **current phase open by default**.
- A collapsed header: a phase-colour dot (`TrainingPhase.color`) + `displayName` + date range + week count + a status indicator (✅ completed / "week 3/8" for current / 🔒 future).
- Expanded: target rows (reusing `PhaseProgressCard`) + milestone rows (target date + a satisfied checkmark, the style of `MilestoneTimelineRow`). Label taper targets as "(max)".
- Integration: replace `milestonesSection(goal:periResult:)` (r415-432) with this component; keep the `phaseSegments` bar as a compact overview above it (now consistent through the shared helper).

#### Story breakdown

* **✅ Story 60.1 — Service + value types + window unification.** `PhaseTimeline`/`PhaseSummary`/`PhaseTarget`/`PhaseMilestone`/`PhaseWindow`/`PhaseStatus` (`Models/PhaseTimeline.swift`) + `PhaseWindowCalculator` as the sole source for phase windows (a week budget, consistent with the bar). `ProgressService.phaseTimeline(for:activities:now:)` builds all four phases with targets (longest session + weekly TRIMP) and buckets the blueprint milestones per phase on deadline; blueprint-less goals get a generic TRIMP target. 9 unit tests in `PhaseTimelineTests` (windows, contiguity, short-goal compression, status, bucketing, taper inversion, future-nil, fallback, logged activity). *Scope note:* the coach path `BlueprintGap.currentPhase` (via `TrainingPhase.calculate`) is deliberately untouched — only the view layer (bar + list) is unified; full unification of the prompt path is a possible follow-up.
* **✅ Story 60.2 — UI `PhaseMilestonesView`.** A `DisclosureGroup` per phase (the first in the codebase), the current phase open by default; closed = a phase-colour dot + name + date range + status, open = target rows (a progress bar, taper "(max)") + milestone rows (target date + a checkmark). Integrated into `GoalsListView` instead of the old four-point timeline; `phaseSegments` now draws from the same `PhaseWindowCalculator` (bar + list can no longer diverge). Dead code removed (`milestonesSection`, `milestonesForGoal`, `GoalMilestoneItem`, `MilestoneTimelineRow`).
* **✅ Story 60.3 — i18n.** Catalog keys NL/EN/DE/ES for the new labels + the format key `Streefdatum %@`; "Now"/"Longest session" reused; phase names stay English (`displayName`). Verified via the compiled `.lproj` (en/de/es), incl. the `%@` key (§13). On-device validation is in the PR checklist.

#### Open points / decisions

- **Computed vs. stored**: everything stays *computed* (no `@Model`, no migration). Consider a `@Model` only if the user wants to add/edit milestones manually — outside this scope.
- **Blueprint-less goals**: `detectBlueprintType` returns `nil` for goals without a marathon/half-marathon/cycling-tour keyword → no `essentialWorkouts`/km targets. Fallback: show the four phases with dates + a generic weekly TRIMP target (`computedTargetTRIMP`), without per-milestone km targets.
- **Detail density**: keep the collapsed view deliberately minimal (no card overload); detail only on expansion.
- **Pickup trigger**: the user wants to see more concretely "what should I hit and when" per phase.

---

### ✅ Epic #61: Security hardening — privacy & storage discipline (review follow-up)

A follow-up to a full security review of the codebase (June 2026: a multi-agent static review per security dimension, every finding adversarially and manually verified). The review confirmed a **healthy starting position**: no critical or high findings and no remotely-exploitable weaknesses. TLS is enforced correctly (no cert-validation footguns), OAuth runs via the OS-hardened API with CSRF protection, secrets are not in the git history and API keys live in the Keychain. The points to follow up are almost all in **protection of health data at rest and observability discipline** — local in nature, none remotely reachable, and each cheap to fix.

> 🔒 **Detail deliberately kept out of the repo.** The concrete locations, severity ratings and remediation notes are in a separate report **outside** the repository (`~/Development/vibecoach-security-review-2026-06-24.md`) — **do not commit**. This ROADMAP description and the stories stay at the hardening *goal* level, so the plan itself does not become an attack map. Work each story out from that external report.

Priority: four highest-priority points (health data at rest + log hygiene), plus a series of lower-priority hardening and maintenance points. A number of review points were **deliberately accepted** and fall out of scope: the shared proxy-token approach (documented as `C-01`) and the migration fallback that in the extreme can wipe local data (§12) — both deliberate trade-offs we do not reopen here.

**Stories:**

* **✅ Story 61.1 — Enforce log hygiene (§11).** Every release-reachable `print()` in `Services/`/`Models/`/`ViewModels/`/the app entry replaced by an `AppLoggers` call with an explicit `privacy:` modifier; the full coach prompt + raw model response are no longer logged verbatim (only a non-identifying length signal). The PHI dumps in the View layer (raw DB dump, Vibe Score with HRV/sleep, age/BMR) removed; error paths route via `AppLoggers` (new categories `coach`/`trainingPlan`/`notifications`/`deepSync`/`workoutSamples`/`dashboard`). Loose `Logger` instances (DeepSync, WorkoutSamples) centralised in `AppLoggers`; workout UUIDs/activity ids now `privacy: .private`. The remaining `print()`s sit behind `#if DEBUG` and don't ship.
* **✅ Story 61.2 — Make credential storage device-only.** `KeychainService` now uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for all tokens + keys — requiring an unlocked device and staying on the device (out of backups and device transfer). The values can be re-derived on a clean install.
* **✅ Story 61.3 — Protect health data at rest.** An explicit file-protection class (`NSFileProtectionCompleteUnlessOpen`) on the SwiftData store + WAL/SHM sidecars after a successful container init (both the normal and the fresh-DB-fallback path), best-effort per §12. A new pure helper `PHIContextCache` (UserDefaults-injected, §6) clears all cleartext PHI context caches + the `WorkoutInsightCache` on source disconnect/logout (the M-2 minimum + L-9); 4 unit tests. Full relocation of the caches to the protected store is a follow-up (backlog below).
* **✅ Story 61.4 — Safety validation around the AI coach.** A new pure helper `TrainingPlanSafetyValidator` (§6) bounds model-proposed parameters — session duration (≤600 min) and target TRIMP (≤1000, negative→0) — at the single `updatePlan` chokepoint, before storage/display and separate from the prompt (L-2). A new pure helper `PromptInputSanitizer` sanitises externally-synced free text (Strava `activity.name`): control chars/newlines out, whitespace condensed, length capped, a placeholder when empty — applied to the prompt interpolation (L-1). 13 unit tests. Ties into the physiological guardrails from Epic 13.
* **✅ Story 61.5 — Build & robustness hygiene.** Test-only `-UITesting` bypasses in `ChatView` + `AddGoalView` put behind `#if DEBUG` (they can no longer exist in a release binary, L-6). An explicit `timeoutInterval = 30` on all Strava requests (incl. token refresh) and the live/per-stage weather requests (L-4; `HistoricalWeatherService` deliberately keeps the default via its injectable fetcher seam). Strava pagination gets a hard page cap (`maxPages = 50`, logged on reaching it) and the server-driven `Retry-After` is clamped to max 24h (I-8). 3 new clamp tests; existing Strava tests green. *The SDK migration is split off as Story 61.8 (a larger, separate operation).*
* **✅ Story 61.6 — Make location privacy consistent.** A new pure helper `CoordinatePrivacy` (§6) as the sole source for coordinate rounding (0.1° / ~11km). `WeatherManager` (live forecast) and `OpenMeteoForecastClient` (per-stage) now round before the request; `HistoricalWeatherService.roundForPrivacy` delegates to it. The privacy margin no longer depends on the separate `desiredAccuracy` setting (L-5). 5 unit tests (+ the existing weather tests stay green).
* **✅ Story 61.7 — PHI context caches to protected storage (follow-up to 61.3).** A new `@Model CoachContextCache` (a SwiftData singleton, SchemaV6) replaces 17 `@AppStorage` properties in `ChatViewModel` — HRV/sleep scores, per-body-area pain scores, 14-day workout-TRIMP/HR history, nutrition data etc. — that sat as plaintext in `Library/Preferences`. By moving them to the file-protected SwiftData store (lightweight migration V5→V6) they enjoy `NSFileProtectionCompleteUnlessOpen` like all other `@Model` types. `PHIContextCache` now only manages the remaining UserDefaults keys; `StravaAuthService.logout(modelContext:)` clears both sides. `AppTabHostView` injects the `ModelContext` via `chatViewModel.configure(with:)`. 3 migration tests (file-backed, §2.1). **Merged via PR #320. Bugfix PR #322:** `DashboardView` still read `lastAnalysisTimestamp` from the no-longer-updated `@AppStorage` mirror; now directly from `viewModel.lastAnalysisTimestamp`.
* **✅ Story 61.8 — Migration away from the unmaintained AI SDK (split off from 61.5).** Replaces `google/generative-ai-swift` (deprecated upstream, CWE-1104/L-3) with `GeminiRestClient` — a direct URLSession REST client against the Gemini v1beta `/generateContent` endpoint, the same pattern as the OpenAI/Anthropic/Mistral clients. Auth via the `x-goog-api-key` header (not a query param, so the key stays out of access logs). The only external Swift package is thereby removed. The `GenerateContentError` branch removed from the mapper, validator and `isOverload()`. **Merged via PR #321.**

**Status 61.1–61.3:** ✅ PR #316. **Status 61.4:** ✅ PR #317. **Status 61.6:** ✅ PR #318. **Status 61.5:** ✅ PR #319. **Status 61.7:** ✅ PR #320 + bugfix PR #322. **Status 61.8:** ✅ PR #321. **Epic #61 fully completed.**

**Pickup trigger:** Epic #61 (security hardening) fully completed. All eight stories merged. Next priority: **Epic #62** (remaining user-feedback hardening) or see the backlog.

---

### ✅ Epic #62: Remaining user-feedback hardening — forms, permissions & concurrency

Consolidation of the open stories that were left hanging in two otherwise-completed epics: the undelivered hardening groups from **Epic #51** (error messages, validation & visibility) and the optional build-setting promotion from **Epic #39** (Swift 6 strict concurrency). All still relevant — they are unhappy-flow gaps that clash with the Management-by-Exception principle — but none of them is blocking; that's why they were detached from their original epic and bundled here as one forward-looking goal. Full scope + acceptance criteria of the #51 stories are in [issue #265](https://github.com/markclausing/vibecoach/issues/265).

**Stories** (each its own PR):

* **✅ 62.1 — Create & manage goals (was 51.B):** `GoalFormValidator` (pure-Swift, §6) enforces a target date ≥ +7 days (AddGoal/EditGoal date pickers forward-bound + Save gated + inline warning), trims the title on save, and flags an implausible stretch (target finish) time per sport via `plausibleFinishRange`. "Soft-delete" is interpreted as *no stale coach context*: deleting a goal calls the new `ChatViewModel.clearGoalDerivedContext()` (cleared caches re-derive from the remaining goals on the next Dashboard appear) — **not** a DB soft-delete flag, which would mean a schema migration + filtering every `@Query` and contradict the "smallest surface" framing. 12 unit tests in `GoalFormValidatorTests`. **PR #325.**
* **✅ 62.2 — AI provider & API key (was 51.D):** `APIKeyInputValidator` (pure-Swift) auto-trims a pasted key (all whitespace/newlines) and detects a wrong-provider prefix (`sk-ant-`/`sk-`/`AIza`) → inline warning. `APIKeyTestStatusStore` (UserDefaults-injected, §6) persists the "key works" verdict per provider as a SHA256 fingerprint (§11) so it survives a provider switch + app restart. 18 unit tests across `APIKeyInputValidatorTests` + `APIKeyTestStatusStoreTests`. **PR #325.**
* **✅ 62.3 — Onboarding & permissions (was 51.E):** the onboarding HealthKit step is no longer silently skippable — "Nu niet" now shows an explicit confirmation dialog (notifications stay freely optional). New **`PermissionStatusView`** in Settings ("Toestemmingen & achtergrond") is the permission-status overview: HealthKit + notifications with their access level + an "Open Instellingen"/"Sta toe" action. *Skipped/revoked detection:* HealthKit's `.notDetermined` foreground re-prompt already lands via Epic #38, and the Dashboard banner (Epic #38) plus this overview surface a denied/partial grant — the overview reuses Epic #38's `lastHKWorkoutsCount` signal (HealthKit hides read-grant state, so "asked but zero data" = partial). **PR #327.**
* **✅ 62.4 — Data sync — remaining paths (was 51.F3/F4/F6):** three pure-Swift helpers (§6) + wiring. **Captive portal** (F6): `CaptivePortalClassifier` flags an HTML login page returned where JSON was expected (no ATS-exception probe needed); `WeatherManager` marks it, `SyncStatusStore` holds a time-bounded flag, `SyncBannerStateBuilder` gets a `.captivePortal` state (priority just below offline) with its own banner. **Weather non-blocking + retry marker** (F4): `WeatherRetryPolicy` throttles auto-retries after a failure (5-min cooldown); `WeatherManager` records the failure timestamp and clears it on success — the app never blocks on a missing forecast. **HK per-type** (F3): `HealthKitPermissionAudit` maps unavailable critical signals → degraded features ("no HRV → no Vibe Score"), surfaced in `PermissionStatusView` (only `.notDetermined` is used, since HealthKit hides read-grant state). 19 unit tests. **PR #329.**
* **✅ 62.5 — Proactive coach (background) (was 51.G):** `ProactiveNotificationService` now persists each engine's real arming outcome — Engine A's `enableBackgroundDelivery` success/error and Engine B's `BGTaskScheduler.submit` success/error — instead of only logging it. `PermissionStatusView` (the 62.3 overview) shows an **Engine A / Engine B status row** (active / not active / registration failed + the framework error string, §11) plus the live notification-permission status as the pre-check surface. The pure **`PermissionStatusEvaluator`** maps the raw facts to the displayed status. *(No hard runtime gate on Engine B vs. notification permission — BGTask scheduling doesn't depend on it; the missing permission is made visible instead.)* **PR #327.**
* **✅ 62.6 — Strict Concurrency Checking → `Complete` (was 39.3):** `SWIFT_STRICT_CONCURRENCY = complete` set across the build configs. **Scope finding:** in Swift 5 language mode (the project's `SWIFT_VERSION = 5.0`) `complete` surfaces the full concurrency diagnostic as **warnings, not errors** — the build stays green (verified locally: 0 errors, ~748 warnings app+tests). Promoting to *hard errors* needs Swift 6 language mode (`SWIFT_VERSION = 6.0`), which would turn those ~748 into a large Sendable/actor-isolation cleanup — deliberately **deferred** as its own migration (the ROADMAP's "whenever it suits"), with the CI guardrail in **Epic #63 story 63.5** (a `complete` matrix cell). So this story delivers the named setting (full surface now visible) without the multi-day error cleanup. **PR #330.**

**Epic #62 fully completed.** All six stories merged: 62.1/62.2 (PR #325), 62.3/62.5 (PR #327), 62.4 (PR #329), 62.6 (PR #330). Shipped in release **2.2.0** (PR #326). The Swift 6 *error-level* enforcement of 62.6 + the ~748-warning concurrency cleanup are a deliberate follow-up migration (guardrail: Epic #63 story 63.5).

---

### ✅ Epic #65: Refactor review July 2026 — structure & scalability follow-ups

Source: full-codebase refactor review of 2 July 2026 (report: `~/Development/vibecoach-refactor-review-2026-07-02.md`, kept outside the repo as a point-in-time document — the essentials are inlined below so this epic is self-contained). Review verdict: the codebase is healthy — zero `try!`/`as!`, one §12-conform `fatalError`, zero external SPM dependencies, 92 unit-test files, and a mature security baseline after Epic #61 with **no open security issues**. The remaining debt clusters into structure, scalability and hygiene. Stories 65.3 + 65.5 **supersede story 64.3**.

**Scope note:** the review's minor security residuals (three PHI cache keys still in cleartext `UserDefaults` from Story 61.7, a proxy-token rotation runbook, the deferred force-unwrap audit's security framing) were deliberately left out of this epic (maintainer decision 2026-07-02); see the report if ever needed. The force-unwrap audit itself is kept in 65.6 as a pure code-quality item.

**Current state in the code (grounding, verified 2026-07-02 @ `7f05e13`):**

- **`ViewModels/ChatViewModel.swift` — 1,780 LOC god object** with six separable responsibilities: (1) ~20 `cache*()` context setters backed by the SwiftData `CoachContextCache`; (2) prompt assembly — `buildContextPrefix` alone spans ~240 lines (L773–1013), plus `buildTrainingThresholdsBlock`, `getStoredPlanString`, `generateCurrentStatusPrompt`; (3) model lifecycle — `buildGenerativeModel` L538–686 + fallback model + rebuild-on-key-change; (4) transport/orchestration — `sendPromptToAI`, `fetchAIResponse` L1561–1753, retry, cancellation; (5) direct HealthKit/Strava data fetching (`fetchHealthKitRecentWorkouts` / `fetchStravaRecentActivities`); (6) JSON post-processing (`extractCleanJSON`). Additionally, three context parameters (`contextProfile: AthleticProfile?`, `activeGoals: [FitnessGoal]`, `activePreferences: [UserPreference]`) are plumbed through **eight** public methods.
- **Sync/maintenance orchestration lives in the view layer:** `AppTabHostView` L32–143 owns the full auto-sync pipeline — concurrency guard (`isAutoSyncing`), `async let` HK+Strava fan-out, Strava→`ActivityRecord` mapping, an inline TRIMP fallback computation, per-activity `HistoricalWeatherService.enrichRecord` awaits (serial, O(n) latency), dedupe insert, `SyncStatusStore` writes. `DashboardView` orchestrates five maintenance jobs (`refreshChatContextCaches`, `runAutoDedupe`, `runSessionReclassification`, `backfillStravaStreams`, `calculateAndSaveVibeScore`) plus risk assessment and legacy-goal backfill. This is exactly the CLAUDE.md §6 "view-layer orchestration without a clean injection seam → documented-not-tested" exemption zone — and it has kept growing since that rule was written.
- **TRIMP formula duplicated 5×:** the Banister pair `0.64 * exp(1.92 * Δ)` appears in `PhysiologicalCalculator.swift:31` (canonical), `AppTabHostView.swift:110`, `SettingsView.swift:198`, `TRIMPExplainerCard.swift:25+41`, and `ProactiveNotificationService.swift:232`. Four of the five re-hardcode HRmax 190 / HRrest 60 population defaults, while `PhysiologicalThresholdService` exists for per-user thresholds (and the maintainer's own zones deviate from population averages). Any formula/threshold correction will silently miss sites.
- **Unbounded SwiftData queries:** three views `@Query` **all** `ActivityRecord` rows ever synced — `DashboardView.swift:24`, `WorkoutAnalysisView.swift:27` (`allActivitiesForContext`; plus `:1383` in its history sheet) and `GoalsListView.swift:13`; Dashboard additionally holds all `DailyReadiness` and all `Symptom` rows. There are **zero `fetchLimit` usages codebase-wide** and only 10 `#Predicate`s. Every consumer actually needs only a bounded window (burndown 14d, pattern scan 14d, blueprint lookback ~12 weeks, trends ~90d). With dual-source sync (HK + Strava) this becomes thousands of `@Model` objects faulted into memory per tab switch after a few years.
- **`WorkoutSample` retention: none.** Samples are resampled to 5s buckets (≈720 rows per hour of training) and only deleted on per-workout re-ingest (`WorkoutSampleStore.replaceSamples`). Roughly 200–400k rows after two years at ~5 sessions/week. All read paths are per-workout-UUID (good), so retention is purely a storage-size concern.
- **Hygiene residue:** `NSNotification.Name("TriggerAutoSync")` constructed inline at 3 sites; repeated `UserDefaults` string literals (`"vibecoach_lastHKWorkoutsCount"` ×5 across 2 files, `"hasCompletedOnboarding"` ×2, theme keys ×2) despite good existing key-namespace examples (`MigrationFallbackStore.key`, `AppLanguage.storageKey`, `AIModelAppStorageKey`); DEBUG `print()`s emitting workout names in `DashboardView.runPatternDebugReport()` L793–821 (§11 wants `AppLoggers` + `.private`, and the function's empirical-validation purpose — pre-32.3b — is long served); Dutch log strings in `AIFitnessCoachApp.makeModelContainer` and Dutch comments in `.swiftlint.yml` (§5/§10 mandate English); two `ISO8601DateFormatter`s built per sync run in `runStravaAutoSync` (cache them in `AppDateFormatters`); `try? modelContext.save()` swallows errors at `AppTabHostView.swift:133`.
- **Oversized / multi-struct view files (§5 soft cap ±500 LOC):** `ChatView.swift` 15 view structs / 1,444 LOC (coach-card components, move-sheet, nutrition components, `WeatherBadgeView`…); `WorkoutAnalysisView.swift` 1,495; `WeekTimelineView.swift` 8 structs / 954; `GoalsListView.swift` 693; `OnboardingView.swift` 9 structs / 673; residual `SettingsView.swift` 999. The flat `Services/` directory holds 60 files across ≥7 domains (sync, AI/chat, weather, physiology, security, notifications, infra) while `Views/` already got domain folders in 64.1/64.2. `ViewModels/` is chat-only (1 VM + 14 prompt formatters).
- **SwiftLint:** `file_length`/`type_body_length`/`function_body_length` are disabled citing exactly the files above, so the §5 cap has no automated backstop; `force_unwrapping` is off with 77 hits and a promised-but-never-scheduled `chore/force-unwrap-audit`.

**Stories** (each its own branch + PR per §8; Conventional-Commit PR titles per §8.1 — note 65.2 carries a `fix:` type and will count as releasing for release-please):

* **✅ 65.1 — Hygiene sweep (quick wins, zero behaviour change).** Centralised the Banister TRIMP formula in `PhysiologicalCalculator` (new `banisterTRIMP(durationMinutes:normalizedDelta:)` kernel — the single `0.64 * exp` site — plus a `basicFallbackTRIMP(durationSec:avgHR:)` static) and routed the 4 duplicated sites through it (`AppTabHostView`, `SettingsView`, `TRIMPExplainerCard` ×2, `ProactiveNotificationService.banisterTRIMP`); introduced `Notification.Name.triggerAutoSync` + an `AppStorageKeys` namespace enum (`hasCompletedOnboarding`, `lastHKWorkoutsCount`, `userName`, `selectedDataSource`, `colorScheme`); deleted the DEBUG pattern-report `print()`s + call site; translated the `makeModelContainer` Dutch log strings (incl. the `fatalError`) + `.swiftlint.yml` comments to English; moved the ISO8601 formatters into cached `AppDateFormatters` statics and replaced the swallowed Strava `modelContext.save()` with a logged do/catch. *Acceptance met:* `grep -rn "0.64 \* exp" AIFitnessCoach` → 1 hit; `grep -rn 'NSNotification.Name("' AIFitnessCoach` → 0 hits; no `print()` outside `UITestMock*`; SwiftLint `--strict` clean; unit suite green (1105 tests, incl. new `PhysiologicalCalculatorTests` fallback/kernel cases). *Effort:* ~4h. *PR:* `chore/refactor-hygiene-sweep`. **Merged via PR #339. Effort:** ~4h.

* **✅ 65.2 — Bounded data access + `WorkoutSample` retention (scalability).** Added a pure `QueryWindows` helper (Calendar-based rolling cutoffs, §3, captured as `let` for the `#Predicate`s) and bounded the four full-table `@Query`s: `DashboardView` (`ActivityRecord` 26w + `DailyReadiness` 90d + `Symptom` 30d, via a new `init(viewModel:)`), `GoalsListView` (`ActivityRecord` 26w), `WorkoutAnalysisView.allActivitiesForContext` (26w) and `RecentWorkoutsSection` (`fetchLimit` = row count). Window sizing verified per consumer: the widest was `atRiskGoals`'s 16-week burndown block → 26w (~6 months) covers it with margin and matches the sample-retention horizon; readiness consumers need ≤14d (trend) → 90d; symptom consumers read only *today* (`SymptomContextFormatter`) → 30d. Added `WorkoutSampleStore.pruneSamplesOlderThanRetention` (retentionMonths = 6, idempotent, `fetchCount`-guarded, boundary kept) wired opportunistically once-per-session in `DeepSyncService.runIfNeeded` (static session guard). Only `WorkoutSample` rows are pruned — `ActivityRecord` aggregates survive. *Acceptance met:* new `WorkoutSampleRetentionTests` (prunes only beyond window, never newest N months, idempotent, boundary kept), `QueryWindowsTests` (cutoff math) and `BoundedQueryGoldenTests` (14d/7d TRIMP sums + `PeriodizationEngine` output identical for full vs windowed input); SwiftLint `--strict` clean; unit suite green (1116 tests). *Risk note:* changes behaviour at the edges (records older than the window drop out of in-view aggregates) — on-device burndown/trend validation is a maintainer checklist item on the PR. *Effort:* ~1 day. *PR:* `fix/bounded-queries-and-sample-retention`. **Merged via PR #340. Effort:** ~1 day.

* **✅ 65.3 — `ChatViewModel` decomposition (supersedes the ChatViewModel part of 64.3).** Extracted in three steps behind a byte-identical prompt fixture snapshot: (1) `CoachPromptAssembler` (context prefix, thresholds block, `systemInstruction`, stored-plan/status/recovery prompts — pure, AppStorage-free, split over 3 files) + `CoachResponseParser` (markdown/brace JSON extraction + plan decode); (2) `CoachContextStore` (the ~20 `cache*` setters + PHI computed props + the `CoachContextCache` SwiftData bridge + `snapshot()`); (3) `CoachModelProvider` (`buildGenerativeModel`/fallback + lazy cache + key resolution on top of `AIModelFactory`), a `CoachInvocationContext` struct collapsing the 3-param plumbing on the eight public methods, and a `CoachStatusAnalyzer` for the HealthKit/Strava fetch waterfall. `ChatViewModel` is now the thin `@MainActor` orchestrator. *Acceptance met:* `ChatViewModel.swift` = 500 LOC; prompt output byte-identical (`CoachPromptFixtureTests`, written first and kept green through every step); structural markers pinned via `CoachPromptAssembler.structuralPromptMarkers` × `systemInstruction` (`CoachPromptAssemblerTests`); existing `ChatViewModelTests` pass with mechanical renames only (`extractCleanJSON` → `CoachResponseParser`, `invocation:` label); 6 new building-block types registered in `architecture.json` + docRevision 32→33. *Deviations:* dropped dead `rebuildRealModel`/`activeAPIKey`/`storedProviderRaw`; added `CoachStatusAnalyzer` (5th component) to meet the hard ≤500 LOC cap. Unit suite green (1132 tests). *Effort:* ~2 days. *PR:* `refactor/chatviewmodel-decomposition`. **Merged via PR #341. Effort:** ~2 days.

* **✅ 65.4 — Sync & maintenance orchestration out of the view layer.** Extracted `AutoSyncCoordinator` (the whole `performAutoSync` pipeline from `AppTabHostView` — `async let` HK+Strava fan-out, single-in-flight concurrency guard, Strava→`ActivityRecord` mapping + TRIMP fallback, per-source `SyncStatusStore` writes, `lastHKWorkoutsCount` cache, post-HK DeepSync trigger and the foreground HealthKit permission retrigger) and `DashboardMaintenanceRunner` (the ordered stream-backfill → dedupe → reclassification → context-cache refresh sequence from `DashboardView`). Both plain `@MainActor` types with injected seams: two thin new protocols (`HealthKitWorkoutSyncing`, `StravaActivityFetching`) plus `SyncStatusStore` / `UserDefaults` / `ModelContext` / a weather-fetch closure. While moving, the per-record `HistoricalWeatherService` awaits are batched with a bounded (~4) task group (only `Sendable` values cross the task boundary; a per-record failure yields no-weather and never fails the sync). `AppTabHostView` drops to ~120 LOC (TabView + one-line triggers only); `calculateAndSaveVibeScore` + the `.onAppear` cache-priming stay in `DashboardView` as genuinely view-bound glue (documented, not tested). *Acceptance met:* `AutoSyncCoordinatorTests` (concurrency-guard no-op, `.missingToken` silence, HK-failure/count=0 while Strava proceeds, both-succeed counts+status, weather-failure isolation — 5 tests) + `DashboardMaintenanceRunnerTests` (dedupe wiring, idempotency, cache-clear, no-op backfill, full-sequence smoke — 5 tests); `SWIFT_STRICT_CONCURRENCY = complete` build with zero new warnings; unit suite green. CLAUDE.md §6 exemption rewritten to name only the residual view-bound glue. New coordinator types registered in `architecture.json` (docRevision 33→34). No `-UITesting` gate touched (the sync path had none). *Deviations:* the batching lives in the coordinator (fetch/apply split) rather than inside `enrichRecord` — keeps `HistoricalWeatherService.enrichRecord` unchanged for its other caller (`SettingsView`). *Effort:* ~1 day. *PR:* `refactor/autosync-coordinator` (stacked on 65.3). **Merged via PR #342. Effort:** ~1 day.

* **✅ 65.5 — Remaining view splits + `Services/` grouping (absorbs the rest of 64.3).** Pure §5 file splits per the 64.1/64.2 recipe (type names identical, zero semantic/string changes, pbxproj registration per §9): `ChatView` 1444→677 (coach cards / workout cards / move-sheet / nutrition components / weather badge → `Views/Chat/`, 11 files), `WorkoutAnalysisView` 1514→417 (`RecentWorkoutsSection` + `+Charts`/`+Insights` extensions → `Views/WorkoutAnalysis/`, incl. `WorkoutAnalysisHelpers` move), `WeekTimelineView` 954→443 (`Views/WeekTimeline/`, zero access relaxations), `GoalsListView` 705→633 (`Views/Goals/GoalRowView`), `OnboardingView` 673→294 (`Views/Onboarding/`, incl. `OnboardingTemplateView` move), residual `SettingsView` 994→698 (`SettingsConnectionCard`/`SettingsRowV2`/`+Actions`). Then grouped the flat 80-file `Services/` into six domain folders (Sync/ 22 · AI/ 14 · Weather/ 7 · Physiology/ 16 · Security/ 4 · Infra/ 7) via pure `git mv`; 10 coaching/goals-domain files deliberately stay flat (would form a seventh bucket outside scope). The optional `ViewModels/` → `Coach/` rename was consciously skipped. *Acceptance met:* no view file > ~700 LOC; build + full unit suite green after each step (1142 tests, 0 failures); zero type renames (SwiftData untouched); `architecture.json` `file` paths updated for the 59 moved building-block references + docRevision 34→35. Access relaxations (`private` → internal) limited to members the cross-file extension splits require — listed per file in the PR body. *Effort:* ~1 day. *PR:* `chore/view-splits-services-grouping` (stacked on 65.4). **Merged via PR #343. Effort:** ~1 day.

* **✅ 65.6 — Lint guardrails + force-unwrap audit (code quality).** Executed the long-deferred `chore/force-unwrap-audit`. **Part 1 (force-unwrap):** enabled SwiftLint `force_unwrapping` (warning) and triaged all 82 hits — every one benign, **zero genuinely-unsafe unwraps found** (consistent with the review's "zero `try!`/`as!`" verdict), so 0 fixed / 82 annotated across five reasoning classes: built-in HealthKit identifiers (file-level disable on `HealthKitPermissionTypes`/`HealthKitManager`, plus `HealthKitSyncService`/`UserProfileService`), hardcoded URL/TimeZone literals (`AIModelFactory` ×7, three Weather clients), fixed-offset `Calendar` date arithmetic (view + HK files), and nil-checked idioms SwiftLint can't see (`guard x == nil || x!`, `!isEmpty` then `.first!`, filtered arrays, ternary nil-check). Each benign site carries a scoped `swiftlint:disable[:next]` + reason, so the rule now keeps *new* unjustified unwraps out. **Part 2 (size backstop):** re-enabled `file_length` (warning 600) + `type_body_length` (warning 500) — an automated backstop under the §5 ±500 LOC soft cap — with in-file `swiftlint:disable` headers on the five files over the file cap (`DashboardView`, `SettingsView`, `ChatView`, `GoalsListView`, `HealthKitManager`) and the two over the type cap (`DashboardView`, `SettingsView`); `blanket_disable_command` allows the unpaired form for those two whole-file rules only. *Acceptance met:* SwiftLint `--strict` green with the new rules; full unit suite green (1142 tests, 0 failures); zero user-facing string changes; no building-block change (architecture.json n/a). *Effort:* ~0.5 day. *PR:* `chore/force-unwrap-audit` (stacked on 65.5; both halves in one PR). **Merged via PR #344. Effort:** ~0.5 day.

**Suggested order:** 65.1 → 65.2 → 65.3 → 65.4 → 65.5 → 65.6, but only 65.6's size-rules half has a hard dependency (on 65.3/65.5). 65.1 and the force-unwrap audit are ideal gap-filler PRs. Total effort: **~6–9 working days**, spread opportunistically.

**Pickup trigger (epic-level):** 65.1 is safe to start anytime; the epic as a whole earns priority the moment dashboard latency is felt, the coach prompt needs a new context type, or a sync-adjacent feature (Epic #59) comes up — those map to 65.2, 65.3 and 65.4 respectively.

---
