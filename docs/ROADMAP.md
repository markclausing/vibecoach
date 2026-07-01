# VibeCoach Roadmap

**Live plan:** open & active work. Completed epics (full history) → **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**. This file deliberately stays short so it is cheap to load as context (for humans and AI agents alike); detail on completed work lives in the archive.

Legend: ✅ done · 🔄 active · ⏳ backlog

---

## Open work (at a glance)

| Epic | What it is | Pickup trigger |
|---|---|---|
| ⏳ **#64** | Refactor-review follow-ups: split the oversized view files (§5), plus small backlog cleanups | next time you open `DashboardView`/`SettingsView`, or when a file over ±500 LOC gets in the way |
| ⏳ **#63** | CI pipeline extensions (promoted from the Epic #46 backlog): TestFlight deploy, snapshot tests, dependency scan, perf checks, concurrency matrix, release-please | each story has its own trigger (first release, UI regression, Swift 6 upgrade…) |
| ⏳ **#59** | Strava Developer Program compliance: base-URL change (June 2027), check AI-data terms | approaching Strava deadlines |
| ⏳ **idea** | Mental benefit of workouts (not yet worked out) | more "why am I training this" context wanted |

---

## Active & planned

### ⏳ Epic #64: Refactor-review follow-ups (tech debt)

Follow-ups from the July 2026 refactor review (dead code · duplicate functionality · oversized files). The first two steps are **done and merged**; the rest is deferred, low-risk, mechanical cleanup — picked up opportunistically, not committed to a sprint.

**Already delivered (context):**
- ✅ **Dead-view cleanup** — removed 10 unreferenced SwiftUI `View` structs (−977 LOC). **Merged via PR #334.**
- ✅ **`AppDateFormatters` helper** — centralised ~40 inline `DateFormatter()` sites into one cached factory (display / prompt / fixed locale intents), fixing two latent i18n bugs. **Merged via PR #335.**

**Stories** (each its own `chore/` PR; pure file-splits per §5 — type names stay identical, so SwiftData and callers notice nothing):

* **✅ 64.1 — Split `DashboardView.swift`** (was ~1700 LOC). Extracted the standalone card/banner structs into their own files under `Views/Dashboard/`: `TRIMPExplainerCard`, `VibeScoreExplainerCard`, `PostWorkoutCheckinCard` (+ `WorkoutCheckinConfig`), `HealthKitPermissionWarningBanner`, `DashboardBannerView`, `MilestoneProgressCard`, `SymptomCheckinCard`. `DashboardView.swift` drops to ~1015 LOC; each extracted file is well under the ±500 LOC cap. Pure file-split — type names unchanged, no functional change; none of the moved sub-views was registered in `architecture.json` (they are internal dashboard components), so no derived-artefact change. Build green. **Merged via PR #336.**
* **⏳ 64.2 — Split `SettingsView.swift`** (~2180 LOC). Pull `AIProviderSettingsView` (~365 LOC), `PreferencesListView` + the memory-type classification, and `PhysicalProfileSection` into separate files. Same acceptance as 64.1. **Pickup trigger:** next substantial edit to Settings.
* **⏳ 64.3 — Split the remaining oversized views opportunistically:** `ChatView`, `WorkoutAnalysisView`, `ChatViewModel` (extract JSON-parsing + PHI-context helpers into `extension` files). Lower priority than 64.1/64.2. **Pickup trigger:** when one of these files gets in the way of a change.
* **⏳ 64.4 — Small backlog cleanups:** resolve or remove the `TODO(Epic 34.3)` placeholder in `ChatView` (real `CoachAnalysisService` LLM call vs. drop the stale marker), and drop the now-stale "V2.0" MARK labels left over from the removed V1 structs. **Pickup trigger:** meltable into any nearby PR.

**Pickup trigger (epic-level):** opening `DashboardView`/`SettingsView` for other work, or any file over ±500 LOC (§5 soft cap) becoming a navigation burden. No functional change in any story — purely structural, so on-device validation is a smoke test that the affected screens still render.

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
* **⏳ 63.5 — Concurrency-strict build as a matrix cell (was 46.B5):** a matrix cell on the build that compiles with `SWIFT_STRICT_CONCURRENCY=complete`, so new `Sendable`/actor-isolation regressions surface as a CI fail without breaking the main build. **Builds on Epic #62 story 62.6** (now ✅, archived — it set `SWIFT_STRICT_CONCURRENCY = complete`, surfacing the full concurrency surface as warnings). This CI cell is the guardrail that turns a *new* concurrency regression into a CI fail without breaking the main build. Acceptance: a newly-introduced concurrency warning fails the matrix cell while the default build stays green. Effort: ~1h. **Pickup trigger:** now unblocked (62.6 done) — pick up when you want the regression guard, or as the first step toward the deferred Swift 6 error-level migration.
* **✅ 63.6 — Semver via `release-please` + git-tag-based marketing version (was 46.B6):** delivered in three parts: (1) `.github/workflows/release-please.yml` (`googleapis/release-please-action@v4`, scoped `contents: write` + `pull-requests: write` so the test pipeline stays least-privilege) + `release-please-config.json` (`release-type: simple`, `include-component-in-tag: false`) + `.release-please-manifest.json` seeded at `2.0.0` — the bot maintains a rolling Release PR that, on merge, creates the `v<x.y.z>` tag + a GitHub Release with changelog, bump derived from Conventional Commits; (2) the existing "Set Build Number from Git" Run Script Build Phase extended to also stamp `CFBundleShortVersionString` from `git describe --tags --abbrev=0` (strip `v`) into the **built** `.app`'s Info.plist, falling back to the source value (`2.0.0`) for tag-less builds — the tag is the build-time source of truth, no `MARKETING_VERSION` mutation in `project.pbxproj` (keeps its `skip-worktree` flag, §9); (3) Conventional Commits formalised as a hard rule in **CLAUDE.md §8.1**, keyed on the **PR title** since we squash & merge. **Maintainer prerequisite (one-off):** enable Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests" so `GITHUB_TOKEN` can open the Release PR. **Merged via PR #323. Effort:** ~2h.

**Suggested order (remaining):** 63.1 (TestFlight, once you do a release — builds on 63.6's tags), 63.5 (right after 62.6 lands), 63.2 (when a visual regression bites), and 63.3 + 63.4 opportunistically (both low-value until their precondition/need exists).

**Pickup trigger (epic-level):** the first real release (drives 63.6 + 63.1), the now-unblocked 63.5 regression guard (Epic #62 story 62.6 is done), or a concrete regression that the current pipeline misses (drives 63.2/63.4).

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

- ✅ **#62** Remaining user-feedback hardening — forms, permissions & concurrency
- ✅ **#61** Security hardening — privacy & storage discipline (review follow-up)
- ✅ **#60** Per-phase milestone insight in the Goals view (collapsible)
- ✅ **#58** README as showcase — user-focused product page
- ✅ **#37** Internationalisation & English-language codebase (NL/EN/DE/ES)

Full history (Phases 1–9 + all completed epics) is in **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**.
