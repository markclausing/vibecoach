# VibeCoach Roadmap

**Live plan:** open & active work. Completed epics (full history) → **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**. This file deliberately stays short so it is cheap to load as context (for humans and AI agents alike); detail on completed work lives in the archive.

Legend: ✅ done · 🔄 active · ⏳ backlog

---

## Open work (at a glance)

| Epic | What it is | Pickup trigger |
|---|---|---|
| ⏳ **#63** | CI pipeline extensions — TestFlight deploy (63.1, **maintainer wants this**), concurrency baseline guard (63.5), snapshot tests + dep scan (63.2+63.3 coupled) | 63.1: as soon as the maintainer's App Store Connect prerequisites are in place; others per-story |
| ⏳ **#69** | Mental benefit of workouts — subjective track first (existing rpe/mood check-in data) | more "why am I training this" context wanted |
| ⏳ **#71** | Objective session comparison in the Coach analysis — "vs. your recent similar sessions", GPS/weather-normalised | wanting "is this normal for me?" context in the workout analysis |
| ⏳ **#59** | Strava Developer Program compliance: base-URL refactor (59.1 anytime) + flip (June 2027), terms verification | Strava migration docs appearing / early 2027; 59.1 fits any quiet moment |
| ⏳ **#68** | Oversized-file splits: 4 files above the 600-LOC lint cap (residual from archived Epic #64) | next time one of the listed files is opened for other work |

---

## Active & planned

### ⏳ Epic #63: CI pipeline extensions (promoted from the Epic #46 backlog)

The six deliberately-deferred CI extensions from completed **Epic #46** were kept as a loose backlog list. Promoted here to a structured epic so each item has a grounded story, acceptance criteria and a clear dependency/trigger — each is picked up independently when its trigger arises. The original short rationale per item lives in the [archive (Epic #46)](ROADMAP-archive.md).

**Current state in the code (grounding):**

- **`.github/workflows/ios-tests.yml`** — a 4-job DAG on `macos-latest`: `lint` (SwiftLint `--strict`, parallel, no `needs:`), `unit-tests` (`xcodebuild test -only-testing:AIFitnessCoachTests -enableCodeCoverage YES`, uploads `UnitTests.xcresult` 7d), `ui-tests` (`needs: unit-tests`, sequential `-parallel-testing-enabled NO`, forced `-testLanguage nl`, uploads `UITests.xcresult` + CoreSimulator diagnostics 14d), `coverage-report` (`needs: [unit-tests, ui-tests]`, runs even on a red ui-tests job, markdown via `scripts/coverage-report.py`, 30d). Least-privilege `permissions: contents: read`; `concurrency` cancels superseded runs.
- **`.github/workflows/codeql.yml`** — separate scan on push + PR + a weekly `cron: '0 6 * * 1'`, matrix runner.
- **Versioning (63.6 ✅)** — `CFBundleVersion` = commit count (Build Phase); marketing version stamped from the latest `v*` tag via `release-please` (see §8.2). Both are exactly what a TestFlight upload needs: monotonic unique build numbers, semver marketing version.
- **Concurrency (62.6 ✅)** — `SWIFT_STRICT_CONCURRENCY = complete` is already set **project-wide**; in Swift 5 language mode this surfaces ~748 diagnostics as *warnings* (build stays green). This invalidates the original 63.5 story text — see the redesigned story below.
- **SPM surface** — **zero external SPM dependencies** (Epic #61.8 removed the last one). 63.2 would introduce the first → which is precisely 63.3's precondition; the two stories are coupled.

**Stories** (each its own PR; renumbered from 46.B1–B6, mapping preserved):

* **⏳ 63.1 — TestFlight deploy on merge to main (was 46.B1; maintainer confirmed the wish, July 2026):** a `deploy-testflight` job in `ios-tests.yml` with `needs: [unit-tests, ui-tests]` and `if: github.ref == 'refs/heads/main' && github.event_name == 'push'`. **Toolchain: pure `xcodebuild`, no fastlane** — keeps the zero-external-dependency stance. Job design:
  1. *Signing bootstrap* — decode `DIST_CERT_P12` (base64) into a throwaway keychain (`security create-keychain` → `import` → `set-key-partition-list`), install the App Store provisioning profile from `PROVISIONING_PROFILE_B64` into `~/Library/MobileDevice/Provisioning Profiles/`.
  2. *Archive* — `xcodebuild archive -scheme AIFitnessCoach -configuration Release -destination 'generic/platform=iOS'` with `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="Apple Distribution"`, `PROVISIONING_PROFILE_SPECIFIER`. The existing Build Phase stamps build number (commit count — monotonic, satisfies TestFlight's unique-build rule) and marketing version (latest `v*` tag, 63.6).
  3. *Export + upload in one step* — `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist` with `method: app-store-connect` + `destination: upload`, authenticated via `-authenticationKeyPath` (the `.p8` from `ASC_API_KEY_P8`) + `-authenticationKeyID` + `-authenticationKeyIssuerID`. No `altool` (deprecated). `ExportOptions.plist` is committed (contains no secrets: method, team ID, destination).
  4. *Cleanup* — delete the throwaway keychain in an `if: always()` step; upload the xcodebuild log as artifact on failure.

  **Maintainer prerequisites (one-off, ~1–2h, blocking):** (1) Apple Developer Program membership; (2) app record + bundle ID in App Store Connect; (3) an ASC API key (App Manager role) → secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8`; (4) an Apple Distribution certificate as .p12 → `DIST_CERT_P12`, `DIST_CERT_PASSWORD`; (5) an App Store provisioning profile → `PROVISIONING_PROFILE_B64`. Six GitHub Secrets total, referenced only via `secrets.*`, never inlined. **Acceptance:** a green merge to main lands a processed build in TestFlight without a manual archive; `permissions:` stays least-privilege (upload auth goes via the ASC key, not `GITHUB_TOKEN`). Effort: ~4–6h incl. first-run debugging. **Pickup trigger:** active — first story to pick up once the maintainer prerequisites exist.
* **⏳ 63.2 — Snapshot tests (was 46.B2):** integrate `pointfreeco/swift-snapshot-testing` and add a `snapshot-tests` job with `needs: unit-tests`. PNG references for the four core screens (Dashboard, Goals, Chat, Settings) checked into the repo; CI then fails on a visual diff. Reuse the existing `UITestMockEnvironment` (`-UITesting`) so renders are deterministic and offline. **Coupling: this adds the project's first external SPM dependency → land 63.3 (~30 min) in the same PR or immediately after.** Acceptance: a deliberate layout regression turns the job red; reference images are committed and reviewable; the job is hard-blocking only after a stable first baseline. Effort: ~6–8h (library + 5–10 references). **Pickup trigger:** a visual regression the XCUITests miss (they assert structure/identifiers, not pixels).
* **⏳ 63.3 — Dependency vulnerability scan (was 46.B3):** GitHub's `dependency-review-action` on PRs that touch `Package.swift`/`Package.resolved`, comparing new transitive deps against the GitHub Advisory Database. **Precondition arrives via 63.2** — the snapshot-testing library would be the first external SPM dep worth scanning. Acceptance: a PR that adds a vulnerable dep is flagged; a clean PR passes silently. Effort: ~30 min. **Pickup trigger:** the 63.2 PR (bundle it), or any other first third-party SPM dependency.
* **⏳ 63.4 — Performance regression checks (was 46.B4):** a `perf` job that tracks build time (parsed from `xcodebuild` output) and/or a light `XCTMetric` baseline (app-launch + dashboard-render), with a historical artifact for comparison. Start as **non-blocking** (report-only) — perf baselines are noisy on shared runners, so gate-on-regression only after the variance band is understood. Acceptance: a baseline artifact is produced per run; a >X% regression is surfaced as a warning (not a hard fail initially). Effort: ~4h. **Pickup trigger:** reported subjective slowness + a need for objective baselines.
* **⏳ 63.5 — Concurrency regression guard (was 46.B5; story redesigned July 2026):** the original text ("a matrix cell that compiles with `SWIFT_STRICT_CONCURRENCY=complete`") is **obsolete as written**: 62.6 already set `complete` project-wide, and in Swift 5 language mode it emits **warnings** (~748 across app+tests) — a plain matrix cell shows nothing new, and warnings-as-errors would fail on all existing debt at once. Redesign as a **baseline-count guard**:
  1. a `concurrency-guard` job (parallel, no `needs:`) runs `xcodebuild build`, greps the log for concurrency diagnostics (`is not concurrency-safe`, `actor-isolated`, `Sendable`), normalises to `file: message` (dropping line numbers — an exact `file:line` baseline is brittle under unrelated edits) and deduplicates;
  2. compares against a checked-in `ci/concurrency-baseline.txt`;
  3. **fails when new entries appear** (listed in the job summary); passes when entries disappear, with a nudge to re-freeze the shrinking baseline.

  **Acceptance:** a PR introducing a new actor-isolation/Sendable warning fails the job naming the diagnostic; removing warnings never fails. **Endgame** remains the deferred Swift 6 language-mode migration (`SWIFT_VERSION = 6.0` turns all ~748 into hard errors — its own multi-day epic); this guard stops the debt growing until then. Effort: ~2–3h (up from ~1h pre-redesign). **Pickup trigger:** unblocked — pick up whenever the regression guard is wanted.
* **✅ 63.6 — Semver via `release-please` + git-tag-based marketing version (was 46.B6):** delivered in three parts: (1) `.github/workflows/release-please.yml` (`googleapis/release-please-action@v4`, scoped `contents: write` + `pull-requests: write` so the test pipeline stays least-privilege) + `release-please-config.json` (`release-type: simple`, `include-component-in-tag: false`) + `.release-please-manifest.json` seeded at `2.0.0` — the bot maintains a rolling Release PR that, on merge, creates the `v<x.y.z>` tag + a GitHub Release with changelog, bump derived from Conventional Commits; (2) the existing "Set Build Number from Git" Run Script Build Phase extended to also stamp `CFBundleShortVersionString` from `git describe --tags --abbrev=0` (strip `v`) into the **built** `.app`'s Info.plist, falling back to the source value (`2.0.0`) for tag-less builds — the tag is the build-time source of truth, no `MARKETING_VERSION` mutation in `project.pbxproj` (keeps its `skip-worktree` flag, §9); (3) Conventional Commits formalised as a hard rule in **CLAUDE.md §8.1**, keyed on the **PR title** since we squash & merge. **Maintainer prerequisite (one-off):** enable Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests" so `GITHUB_TOKEN` can open the Release PR. **Merged via PR #323. Effort:** ~2h.

**Suggested order (remaining):** 63.1 first (maintainer wish confirmed; blocked only on the one-off Apple prerequisites), then 63.5 (unblocked, cheap), 63.2+63.3 as a pair when a visual regression bites, 63.4 opportunistically.

**Pickup trigger (epic-level):** the TestFlight wish (63.1, active), the unblocked 63.5 regression guard, or a concrete regression the current pipeline misses (63.2/63.4).

---

### ⏳ Epic #69: Mental benefit of workouts — subjective track first

Goal: the coach can say *"sessions like this usually give you energy"* — grounded in the user's own data, not generic claims. Direction chosen (July 2026): **subjective first** — build on the existing post-workout check-in data (`ActivityRecord.rpe` 1–10 + `ActivityRecord.mood` emoji, Epic 18) rather than new sensor pipelines. An objective HRV/sleep track stays a deferred follow-up story.

**Design constraints (grounding):**

- `mood` is an optional `String` emoji (`"😌"`, `"🟢"`, `"🚀"`, `"🤕"`, `"🥵"`); `rpe` an optional `Int`. Coverage is partial — the profiler must tolerate sparse data and stay silent below a sample threshold.
- §1 management-by-exception: this is *positive* context, not an alert — surface it in analysis/chat, never as a warning or banner.
- §2 type-safety: map the raw emoji to a `MoodValence` enum (positive/neutral/negative) **inside the profiler at read time** — no schema change, no migration; unknown emoji → excluded.

**Stories:**

* **⏳ 69.1 — `MentalBenefitProfiler` (pure Swift, `Services/`):** input `[ActivityRecord]`, injected by the caller (AppStorage-free per §6); trailing 90-day window via `Calendar.date(byAdding:)` (§3, never TimeInterval math). Groups mood-tagged sessions by `SessionType` (+ `SportCategory`), computes a valence distribution per group, and emits a `MentalBenefitProfile` **only** when a group has ≥5 mood-tagged sessions *and* a clear skew (e.g. ≥70% positive valence) — below either threshold: no claim (silence beats noise). Also expose the inverse signal (a group that consistently ends in 🤕/🥵 at high RPE) as *data*, framing left to the coach. Unit tests: threshold boundaries, sparse/empty data, unknown emoji, window edge across a DST transition.
* **⏳ 69.2 — Coach-prompt integration:** the prompt formatter emits a new structural marker section `[MENTAL BENEFIT]` when at least one profile exists, and the `systemInstruction` reference gains the matching section description — **both sides in the same PR, grep both after the change (§13 structural-marker rule).** Interpolated values follow the existing prompt-vs-UI split (prompt terms stay the internal convention; output language via the existing `respond in {language}` directive).
* **⏳ 69.3 — UI surfacing:** one contextual line in `WorkoutAnalysisView` (e.g. "Sessies zoals deze geven je meestal energie") when the analysed workout's session type has a profile. Every new user-facing string hand-added to `Localizable.xcstrings` (NL source + EN/DE/ES) + `swift scripts/normalize-xcstrings.swift` (§13 — extraction is off). README check: touches the `04-workout-deepdive` showcase surface — expect a copy tweak at most; flag a screenshot refresh if the visual changes.
* **⏳ 69.4 — Objective track (deferred, not committed):** HRV response in the hours after a workout + sleep the following night, correlated against the subjective profile. Needs new HealthKit queries and careful causality framing — only pick up once 69.1–69.3 prove the concept useful on-device.

**Architecture artefacts:** `MentalBenefitProfiler` is a new building-block Service → `architecture.json` + `architecture.html` in the same PR (§7 hard trigger); ARCHITECTURE.md gains a short section (new analysis concept).

**Pickup trigger:** wanting more explicit "why am I training this" context with workouts. No dependency on other epics.

---

### ⏳ Epic #71: Objective session comparison in the Coach analysis

Maintainer decision (July 2026, during the Epic #70 review): the workout-detail **Coach analysis stays purely objective** — the subjective workout-chat facts (Epic #70) deliberately do **not** feed `WorkoutInsightService`, so the analysis keeps its independent "what does the data say" value and the divergence with the user's own story stays visible (the chat below it is where both meet). What the analysis *should* get is objective context: **"how does this session compare to my recent similar ones?"** — with GPS and weather used to make sessions genuinely comparable (same route, humidity-normalised expectations).

**Current state in the code (grounding):**

- `ActivityRecord` already carries everything needed for cheap comparison: scalar metrics (distance, `movingTime`, `averageHeartrate`, `trimp`), **weather** (`temperatureCelsius`/`humidityPercent`, Epic #49) and **GPS start coordinates** (`startLatitude`/`startLongitude`, Epic #52). Note: start point only — no track — so "same route" is a start-proximity + distance-band heuristic, never a track match.
- `WorkoutSample` rows are pruned after **6 months** (`WorkoutSampleService.retentionMonths`, story 65.2) → pattern-level comparison (decoupling/drift of past sessions) is only recomputable inside that window; scalar comparison works for the full 26-week activity window.
- `WorkoutInsightService.InsightContext` is a struct of optional context strings (`periodizationContext`, weather, …) — one more optional slots in cleanly; `buildPrompt` appends blocks conditionally.
- The insight cache key is already a composite fingerprint (pattern + profile + goals + weather + cadence, see `WorkoutAnalysisView+Insights`) — a comparison-set fingerprint extends it, so a changed match set regenerates the narrative automatically.

**Stories:**

* **⏳ 71.1 — `SimilarSessionMatcher` (pure Swift, `Services/`):** input `(target: ActivityRecord-values, candidates: [ActivityRecord-values])` as value tuples/structs (AppStorage-free, §6). Hard filters: same `SportCategory`, started within the trailing 6 months (aligned with sample retention), not the target itself. Scoring: same `SessionType` (strong weight), duration band ±25%, distance band ±25%, **GPS start proximity** (Haversine on start coords; ≤ ~500 m marks a *same-route candidate*), recency tiebreak. Output: top 3 matches + their same-route flags. Unit tests: each filter, scoring order, the 500 m boundary, missing GPS/weather → still matchable (fields optional), fewer than 3 candidates → fewer results.
* **⏳ 71.2 — `SessionComparisonFormatter` (pure):** renders the `[SESSION COMPARISON]` block: one line per match — prompt-formatted date (`AppDateFormatters.promptStyle`, §13), distance, duration, avg HR, pace, TRIMP, temp/humidity when present, `same route` marker when flagged. No interpretation in the formatter — deltas and conclusions are the model's job. Empty matches → `""` (no block, house convention). Unit tests: line format, marker, missing-weather omission, empty → empty.
* **⏳ 71.3 — Pattern-level enrichment (optional, separate story):** for matched sessions that still have samples (≤ 6 months): fetch via `WorkoutSampleService.samples(forWorkoutUUID:)` (`UUID.forActivityRecordID` mapping) and run the existing detectors to add per-session decoupling/drift to the comparison lines — that turns "your HR was higher" into "your decoupling was 6.2% vs 4–5% on the same route". Degrade gracefully when samples are pruned (scalar line only). Watch the cost: 3 extra sample fetches + detector runs on page open — run inside the existing insight task, measure before optimising. Ship 71.1+71.2+71.4 first; this story only if the scalar comparison proves too shallow.
* **⏳ 71.4 — Prompt + cache integration:** `InsightContext` gains `comparisonContext: String?`; `buildPrompt` appends the block + instruction text telling the coach to (a) name concrete deltas vs. the matched sessions, (b) **weather-normalise** expectations ("at 87% humidity vs ~60% on your previous three, some extra drift is expected — don't read it as lost fitness"), (c) prefer same-route matches for pace comparisons. `WorkoutAnalysisView+Insights` computes the matches (it already queries `allActivitiesForContext`, 26 weeks) and extends the cache fingerprint with a hash of matched ids + key metrics. No new UI surface: the analysis narrative carries the comparison (optionally a "vs. N vergelijkbare sessies" caption chip — decide during on-device review).

**Deliberately out of scope:** subjective facts in the insight (decided against, see intro); cross-sport comparison; full GPS-track matching (no track data stored).

**Architecture artefacts (§7):** `SimilarSessionMatcher` + `SessionComparisonFormatter` are new building blocks → `architecture.json` + `.html` in the same PR; ARCHITECTURE.md §-note under the workout-analysis section.

**Effort estimate:** ~1–1.5 day (71.1 ~3–4h · 71.2 ~2h · 71.4 ~2–3h; 71.3 +~4h if picked up).

**Pickup trigger:** wanting "is this normal for me?" context in the workout analysis — natural companion to Epic #69 (both enrich the analysis layer), no dependency on it.

---

### ⏳ Epic #59: Strava Developer Program changes — compliance & continuity

Strava [announced changes to the Developer Program](https://communityhub.strava.com/insider-journal-9/an-update-to-our-developer-program-13428) with phased deadlines. VibeCoach reads the user's own activities (HR/power/GPS/streams) via the Strava API and feeds them into the AI coach — impact mapped below.

**Current state in the code (grounding):** the token already goes via the `Authorization: Bearer` header (`FitnessDataService`) → already compliant with the 2027 header requirement. Activity data is fetched **directly** from `https://www.strava.com/api/v3/...` at six call sites in `FitnessDataService` (lines ~123/158/197/235/293/355); only the OAuth token refresh runs via our own Cloudflare Worker (`Secrets.stravaProxyBaseURL`, `/oauth/strava/refresh`, holds the `client_secret`). No club endpoints in use.

**Deadlines & status:**

1. **30 June 2026 — subscription requirement: ✅ CONFIRMED CLOSED (5 July 2026).** The maintainer has a paid Strava subscription and verified on-device that sync keeps working after the deadline passed. Personal use (1 athlete) sits well within the Standard Tier limit of 10. (Should the subscription ever lapse, Strava sync drops out and the app keeps running HealthKit-only.)
2. **1 September 2026 — endpoint deprecations:** Club Activities/Administrators/Members disappear; Segments Explore → Extended Tier only. **No impact expected** (none of these endpoints in use) — 59.3 records the one-line confirmation.
3. **1 June 2027 — base-URL + header changes:** base URL moves to `https://www.api-v3.strava.com`; header auth is already fine. Covered by 59.1 + 59.2 below.
4. **Terms questions (intermediary + AI):** covered by 59.3.

**Stories:**

* **⏳ 59.1 — Centralise the Strava base URL (anytime, low risk):** the six call sites in `FitnessDataService` inline `https://www.strava.com/api/v3`. Extract one constant — e.g. `enum StravaAPI { static let baseV3: URL }` in `Services/Sync/` — and build request URLs via `appending(path:)`/`URLComponents`, so the 2027 flip is a one-line change. Unit-test the URL builders (query composition for the paged `athlete/activities` calls). **Scope note:** `StravaAuthService`'s `https://www.strava.com/oauth/mobile/authorize` is the OAuth **web** endpoint, not `api/v3` — the announcement targets the API base, so keep OAuth out of the constant; verify it is untouched when Strava publishes migration docs.
* **⏳ 59.2 — Flip the base URL (deadline 1 June 2027):** change the 59.1 constant to `https://www.api-v3.strava.com` + a full on-device sync regression (auth → activity list → detail → streams → athlete). **Pickup trigger:** Strava's migration window opening / early 2027 — flip well before the deadline so a broken assumption surfaces with time to spare.
* **⏳ 59.3 — Terms verification (paper only, no code):** (a) **intermediary check** — our Cloudflare Worker only performs first-party OAuth token exchange with our own `client_secret`; activity data flows direct from Strava to the app → likely not a "third-party intermediary platform", confirm against the final terms; (b) **AI/LLM forwarding** — check the API terms on sending the user's *own* activity data to an external LLM (BYOK) and document the conclusion in `ARCHITECTURE.md` (privacy section); (c) the 1 Sept 2026 endpoint confirmation from point 2. Output: a short ARCHITECTURE.md note, no app change expected.

**Also consider (unchanged):** Strava's new MCP tool for personal data analysis as a complementary path, and graceful degradation (app keeps working HealthKit-only if Strava drops out — ties into §12 defensive init).

**Pickup trigger (epic-level):** 59.1 fits any quiet moment (pairs naturally with other `FitnessDataService` work); 59.2/59.3 on Strava's migration docs or early 2027; any Strava-sync failure caused by the program changes escalates the epic immediately.

---

### ⏳ Epic #68: Oversized-file splits (opportunistic backlog)

Residual from archived **Epic #64**: four files still sit above the 600-LOC SwiftLint warning cap (§5) and carry a `// swiftlint:disable file_length` header (debt visible at the point of debt). Splitting is opportunistic — never a sprint, no functional change ever.

| File | LOC (July 2026) | Natural split seam |
|---|---|---|
| `Views/DashboardView.swift` | 882 | remaining inline card/section subviews → `Views/Dashboard/` (the 64.1 pattern) |
| `Views/SettingsView.swift` | 703 | next cohesive `Section` blocks → `Views/Settings/` (the 64.2 pattern) |
| `Views/ChatView.swift` | 680 | coach-card subviews / input-bar components into own files |
| `Services/Sync/HealthKitManager.swift` | 607 | sample-query builders vs. authorization/background-delivery plumbing |

`GoalsListView.swift` (650 LOC) was split by Epic #72 story 72.2 — four components extracted to `Views/Goals/`.

**Rules per split (all established, §5/§9):** each split its own `chore/` PR; pure file-split — type names identical, so SwiftData and callers notice nothing; remove the `swiftlint:disable` header once the file drops under the cap; new files registered in `project.pbxproj` per §9; no `architecture.json` change unless a split promotes a type into a genuine building block. On-device validation = smoke test that the affected screen still renders.

**Pickup trigger:** next time one of the listed files is opened for other work — do the split first (or immediately after) in its own PR.

---

## Recently completed (last 5)

- ✅ **#72** Goals-tab redesign — status verdict, expected-today markers, phase-grouped milestones, finish-time duration fix
- ✅ **#70** Per-workout chat with local memory — "discuss this workout" on the detail page; distilled facts feed plans & feedback
- ✅ **#64** Refactor-review follow-ups — DashboardView/SettingsView splits, stale-marker cleanup; residual oversized files → Epic #68
- ✅ **#67** "How it's built" viewer — visual dev-workflow (agent collaboration, CI pipeline, branching, docs) in the architecture HTML
- ✅ **#66** Architecture-viewer redesign — mobile-first + non-programmer progressive disclosure (Story → Map → Depth)

Full history (Phases 1–9 + all completed epics) is in **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**.
