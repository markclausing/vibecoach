# VibeCoach Roadmap

**Live plan:** open & active work. Completed epics (full history) → **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**. This file deliberately stays short so it is cheap to load as context (for humans and AI agents alike); detail on completed work lives in the archive.

Legend: ✅ done · 🔄 active · ⏳ backlog

---

## Open work (at a glance)

| Epic | What it is | Pickup trigger |
|---|---|---|
| ⏳ **#62** | Remaining user-feedback hardening: form validation, permission visibility, sync edge paths, strict concurrency | a concrete unhappy flow, or before a Swift 6 upgrade |
| ⏳ **#63** | CI pipeline extensions (promoted from the Epic #46 backlog): TestFlight deploy, snapshot tests, dependency scan, perf checks, concurrency matrix, release-please | each story has its own trigger (first release, UI regression, Swift 6 upgrade…) |
| ⏳ **#59** | Strava Developer Program compliance: base-URL change (June 2027), check AI-data terms | approaching Strava deadlines |
| ⏳ **idea** | Mental benefit of workouts (not yet worked out) | more "why am I training this" context wanted |

---

## Active & planned

### ⏳ Epic #62: Remaining user-feedback hardening — forms, permissions & concurrency

Consolidation of the open stories that were left hanging in two otherwise-completed epics: the undelivered hardening groups from **Epic #51** (error messages, validation & visibility) and the optional build-setting promotion from **Epic #39** (Swift 6 strict concurrency). All still relevant — they are unhappy-flow gaps that clash with the Management-by-Exception principle — but none of them is blocking; that's why they were detached from their original epic and bundled here as one forward-looking goal. Full scope + acceptance criteria of the #51 stories are in [issue #265](https://github.com/markclausing/vibecoach/issues/265).

**Stories** (each its own PR):

* **✅ 62.1 — Create & manage goals (was 51.B):** `GoalFormValidator` (pure-Swift, §6) enforces a target date ≥ +7 days (AddGoal/EditGoal date pickers forward-bound + Save gated + inline warning), trims the title on save, and flags an implausible stretch (target finish) time per sport via `plausibleFinishRange`. "Soft-delete" is interpreted as *no stale coach context*: deleting a goal calls the new `ChatViewModel.clearGoalDerivedContext()` (cleared caches re-derive from the remaining goals on the next Dashboard appear) — **not** a DB soft-delete flag, which would mean a schema migration + filtering every `@Query` and contradict the "smallest surface" framing. 12 unit tests in `GoalFormValidatorTests`. **PR #325.**
* **✅ 62.2 — AI provider & API key (was 51.D):** `APIKeyInputValidator` (pure-Swift) auto-trims a pasted key (all whitespace/newlines) and detects a wrong-provider prefix (`sk-ant-`/`sk-`/`AIza`) → inline warning. `APIKeyTestStatusStore` (UserDefaults-injected, §6) persists the "key works" verdict per provider as a SHA256 fingerprint (§11) so it survives a provider switch + app restart. 18 unit tests across `APIKeyInputValidatorTests` + `APIKeyTestStatusStoreTests`. **PR #325.**
* **✅ 62.3 — Onboarding & permissions (was 51.E):** the onboarding HealthKit step is no longer silently skippable — "Nu niet" now shows an explicit confirmation dialog (notifications stay freely optional). New **`PermissionStatusView`** in Settings ("Toestemmingen & achtergrond") is the permission-status overview: HealthKit + notifications with their access level + an "Open Instellingen"/"Sta toe" action. *Skipped/revoked detection:* HealthKit's `.notDetermined` foreground re-prompt already lands via Epic #38, and the Dashboard banner (Epic #38) plus this overview surface a denied/partial grant — the overview reuses Epic #38's `lastHKWorkoutsCount` signal (HealthKit hides read-grant state, so "asked but zero data" = partial). **PR #327.**
* **⏳ 62.4 — Data sync — remaining paths (was 51.F3/F4/F6):** HealthKit per-type permission handling, making a weather error non-blocking with a retry marker instead of a hard interruption, and captive-portal detection (online but behind a login portal).
* **✅ 62.5 — Proactive coach (background) (was 51.G):** `ProactiveNotificationService` now persists each engine's real arming outcome — Engine A's `enableBackgroundDelivery` success/error and Engine B's `BGTaskScheduler.submit` success/error — instead of only logging it. `PermissionStatusView` (the 62.3 overview) shows an **Engine A / Engine B status row** (active / not active / registration failed + the framework error string, §11) plus the live notification-permission status as the pre-check surface. The pure **`PermissionStatusEvaluator`** maps the raw facts to the displayed status. *(No hard runtime gate on Engine B vs. notification permission — BGTask scheduling doesn't depend on it; the missing permission is made visible instead.)* **PR #327.**
* **✅ 62.6 — Strict Concurrency Checking → `Complete` (was 39.3):** `SWIFT_STRICT_CONCURRENCY = complete` set across the build configs. **Scope finding:** in Swift 5 language mode (the project's `SWIFT_VERSION = 5.0`) `complete` surfaces the full concurrency diagnostic as **warnings, not errors** — the build stays green (verified locally: 0 errors, ~748 warnings app+tests). Promoting to *hard errors* needs Swift 6 language mode (`SWIFT_VERSION = 6.0`), which would turn those ~748 into a large Sendable/actor-isolation cleanup — deliberately **deferred** as its own migration (the ROADMAP's "whenever it suits"), with the CI guardrail in **Epic #63 story 63.5** (a `complete` matrix cell). So this story delivers the named setting (full surface now visible) without the multi-day error cleanup. **PR #330.**

**Pickup trigger:** a concrete unhappy flow that hits a user (a goal with a date in the past, a wrongly pasted key, or confusion about which permissions are active), or the wish to enforce concurrency discipline before a Swift 6 upgrade.

**Suggested order:** 62.1 + 62.2 (form validation) ✅ and 62.3 + 62.5 (permission visibility) ✅ done; next 62.4 (sync edge paths), and 62.6 as a standalone concurrency PR whenever it suits.

---

### ⏳ Epic #63: CI pipeline extensions (promoted from the Epic #46 backlog)

The six deliberately-deferred CI extensions from completed **Epic #46** were kept as a loose backlog list. Promoted here to a structured epic so each item has a grounded story, acceptance criteria and a clear dependency/trigger — none is committed yet, and each is picked up independently when its trigger arises. The original short rationale per item lives in the [archive (Epic #46)](ROADMAP-archive.md).

**Current state in the code (grounding):**

- **`.github/workflows/ios-tests.yml`** — a 4-job DAG on `macos-latest`: `lint` (SwiftLint `--strict`, parallel, no `needs:`), `unit-tests` (`xcodebuild test -only-testing:AIFitnessCoachTests -enableCodeCoverage YES`, uploads `UnitTests.xcresult` 7d), `ui-tests` (`needs: unit-tests`, sequential `-parallel-testing-enabled NO`, forced `-testLanguage nl`, uploads `UITests.xcresult` + CoreSimulator diagnostics 14d), `coverage-report` (`needs: [unit-tests, ui-tests]`, runs even on a red ui-tests job, markdown via `scripts/coverage-report.py`, 30d). Least-privilege `permissions: contents: read`; `concurrency` cancels superseded runs.
- **`.github/workflows/codeql.yml`** — separate scan on push + PR + a weekly `cron: '0 6 * * 1'`, matrix runner.
- **Versioning** — `CFBundleVersion` is set at build time by a Run Script Build Phase (`git rev-list --count HEAD`); there is **no** `MARKETING_VERSION` automation and no git tags / GitHub Releases yet. `project.pbxproj` keeps its `skip-worktree` flag (§9).
- **SPM surface** — **zero external SPM dependencies.** Epic #61.8 (PR #321) replaced the last one (`generative-ai-swift`) with the in-repo `GeminiRestClient`, so `Package.resolved` is gone entirely → the dependency-scan story (63.3) has nothing to scan until a genuine third-party package is taken on.

**Stories** (each its own PR; renumbered from 46.B1–B6, mapping preserved):

* **⏳ 63.1 — TestFlight deploy on merge to main (was 46.B1):** a `deploy-testflight` job with `needs: [unit-tests, ui-tests]` and `if: github.ref == 'refs/heads/main'`, via `xcodebuild -exportArchive` (+ `ExportOptions.plist`) or `fastlane`. **Blocked on maintainer setup I can't do:** an Apple Developer account, an App Store Connect API key (`.p8`), and a signing cert + provisioning profile in GitHub Secrets. Acceptance: a green merge to main produces a TestFlight build without a manual archive upload; the `permissions:` block stays least-privilege; secrets are referenced via `secrets.*`, never inlined. Effort: ~4–6h one-off (cert/secret plumbing), then maintenance-free. **Pickup trigger:** the wish to automate distribution instead of uploading an archive by hand — the natural first story once a real release is wanted.
* **⏳ 63.2 — Snapshot tests (was 46.B2):** integrate `pointfreeco/swift-snapshot-testing` and add a `snapshot-tests` job with `needs: unit-tests`. PNG references for the four core screens (Dashboard, Goals, Chat, Settings) checked into the repo; CI then fails on a visual diff. Reuse the existing `UITestMockEnvironment` (`-UITesting`) so renders are deterministic and offline. Acceptance: a deliberate layout regression turns the job red; reference images are committed and reviewable; the job is hard-blocking only after a stable first baseline. Effort: ~6–8h (library + 5–10 references). **Pickup trigger:** a visual regression the XCUITests miss (they assert structure/identifiers, not pixels).
* **⏳ 63.3 — Dependency vulnerability scan (was 46.B3):** GitHub's `dependency-review-action` on PRs that touch `Package.swift`/`Package.resolved`, comparing new transitive deps against the GitHub Advisory Database. **Precondition:** the project currently has **zero** external SPM deps (see grounding), so the action has nothing to review — this only becomes meaningful once a genuine third-party package is added. Acceptance: a PR that adds a vulnerable dep is flagged; a clean PR passes silently. Effort: ~30 min once there is a manifest worth scanning. **Pickup trigger:** adding the first genuine third-party SPM dependency.
* **⏳ 63.4 — Performance regression checks (was 46.B4):** a `perf` job that tracks build time (parsed from `xcodebuild` output) and/or a light `XCTMetric` baseline (app-launch + dashboard-render), with a historical artifact for comparison. Start as **non-blocking** (report-only) — perf baselines are noisy on shared runners, so gate-on-regression only after the variance band is understood. Acceptance: a baseline artifact is produced per run; a >X% regression is surfaced as a warning (not a hard fail initially). Effort: ~4h. **Pickup trigger:** reported subjective slowness + a need for objective baselines.
* **⏳ 63.5 — Concurrency-strict build as a matrix cell (was 46.B5):** a matrix cell on the build that compiles with `SWIFT_STRICT_CONCURRENCY=complete`, so new `Sendable`/actor-isolation regressions surface as a CI fail without breaking the main build. **Depends on Epic #62 story 62.6** (which promotes the project build setting first) — this CI cell is the guardrail that keeps 62.6 from eroding. Acceptance: a newly-introduced concurrency warning fails the matrix cell while the default build stays green. Effort: ~1h once 62.6 is done. **Pickup trigger:** completion of 62.6.
* **✅ 63.6 — Semver via `release-please` + git-tag-based marketing version (was 46.B6):** delivered in three parts: (1) `.github/workflows/release-please.yml` (`googleapis/release-please-action@v4`, scoped `contents: write` + `pull-requests: write` so the test pipeline stays least-privilege) + `release-please-config.json` (`release-type: simple`, `include-component-in-tag: false`) + `.release-please-manifest.json` seeded at `2.0.0` — the bot maintains a rolling Release PR that, on merge, creates the `v<x.y.z>` tag + a GitHub Release with changelog, bump derived from Conventional Commits; (2) the existing "Set Build Number from Git" Run Script Build Phase extended to also stamp `CFBundleShortVersionString` from `git describe --tags --abbrev=0` (strip `v`) into the **built** `.app`'s Info.plist, falling back to the source value (`2.0.0`) for tag-less builds — the tag is the build-time source of truth, no `MARKETING_VERSION` mutation in `project.pbxproj` (keeps its `skip-worktree` flag, §9); (3) Conventional Commits formalised as a hard rule in **CLAUDE.md §8.1**, keyed on the **PR title** since we squash & merge. **Maintainer prerequisite (one-off):** enable Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests" so `GITHUB_TOKEN` can open the Release PR. **Merged via PR #323. Effort:** ~2h.

**Suggested order (remaining):** 63.1 (TestFlight, once you do a release — builds on 63.6's tags), 63.5 (right after 62.6 lands), 63.2 (when a visual regression bites), and 63.3 + 63.4 opportunistically (both low-value until their precondition/need exists).

**Pickup trigger (epic-level):** the first real release (drives 63.6 + 63.1), the completion of Epic #62 story 62.6 (unblocks 63.5), or a concrete regression that the current pipeline misses (drives 63.2/63.4).

---

### ⏳ Epic #59: Strava Developer Program changes — compliance & continuity

Idea for a future Epic — not yet worked out. Strava has [announced changes to the Developer Program](https://communityhub.strava.com/insider-journal-9/an-update-to-our-developer-program-13428) with several phased deadlines. VibeCoach reads the user's own activities (HR/power/GPS/streams) via the Strava API and feeds them into the AI coach — so we need to map the impact and act in time.

**Current state in the code (grounding):** the token already goes via the `Authorization: Bearer` header (`FitnessDataService` lines 119/153/191/229/279/334) → **already compliant** with the 2027 header requirement. Activity data is fetched **directly** from `https://www.strava.com/api/v3/...` (`FitnessDataService`); only the OAuth token refresh runs via our own Cloudflare Worker (`Secrets.stravaProxyBaseURL`, `/oauth/strava/refresh`, holds the `client_secret`). **No** club endpoints in use.

**Deadlines & impact:**

1. **30 June 2026 — subscription requirement (✅ COVERED).** From this date, Standard Tier developers need a paid Strava *subscription* (premium membership) to keep using the API — not just a free account. **Status: the maintainer has a paid Strava subscription, so this requirement is met; no action needed.** Personal use = 1 athlete also sits well within the Standard Tier limit of 10 athletes self-service. (Should the subscription ever lapse, Strava sync drops out and the app keeps running HealthKit-only — see Open points.)
2. **Intermediary-platform ban.** "Apps routing Strava data through third-party intermediary platforms are no longer supported." → Verify whether our own Cloudflare Worker falls under this. It only does OAuth token exchange/refresh (first-party, our own `client_secret`); the **activity data goes directly** from Strava to the app, not via the Worker. Probably not a "third-party intermediary data platform", but confirm against the new terms; reshape the token exchange if needed.
3. **1 September 2026 — endpoint deprecations.** Club Activities/Administrators/Members disappear; Segments Explore only for Extended Tier. → **No impact expected** (the app does not use these endpoints) — confirm briefly.
4. **1 June 2027 — technical changes.** Base URL changes from `https://www.strava.com/api/v3` to `https://www.api-v3.strava.com`; tokens mandatory in request headers. → Code: convert the ~6 hardcoded URLs in `FitnessDataService` + `StravaAuthService` (centralising them in one base-URL constant is a clean refactor at the same time); the header auth is already fine. Small job, plenty of time to plan.
5. **AI scraping / data to an external LLM.** Strava emphasises concerns about AI scraping; the announcement imposes no explicit API-term restriction on AI/ML use, but our coach sends activity data to an external LLM (BYOK). → Check the Strava API terms on whether forwarding the user's **own** data to an AI provider is allowed, and document that (privacy/§11).

**Open points / pickup trigger:** point 1 is **time-critical** (deadline 30 June 2026, maintainer action now). Code work (point 4) can come later in a separate story. Also consider (a) Strava's new **MCP tool for personal data analysis** as an alternative/complementary path, and (b) graceful degradation: confirm the app keeps working HealthKit-only if Strava access drops out (ties into §12 defensive init). **Pickup trigger:** the approaching 30-June deadline, or a Strava-sync failure caused by one of the changes above.

---

### ⏳ Epic backlog: Mental benefit of workouts

Idea for a future Epic — not yet worked out. The thought: show not only physical metrics (TRIMP, HR, recovery), but also something about mood/energy/stress impact so the coach can say "you'll feel good from this for the rest of the day" or "this session helps you wind down stress". Open points: which signals (HRV response after a ride, post-RPE mood, sleep response the following night), which UI (an extra tile under Vibe Score? A field on WorkoutAnalysisView?), how the coach frames this, and how we distinguish it from pure physical load. Pickup trigger: the user wants more explicit "why am I training this" context with workouts.

---

## Recently completed (last 5)

- ✅ **#61** Security hardening — privacy & storage discipline (review follow-up)
- ✅ **#60** Per-phase milestone insight in the Goals view (collapsible)
- ✅ **#58** README as showcase — user-focused product page
- ✅ **#37** Internationalisation & English-language codebase (NL/EN/DE/ES)
- ✅ **#57** Simplify the RPE check-in — one-tap effort + feel

Full history (Phases 1–9 + all completed epics) is in **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**.
