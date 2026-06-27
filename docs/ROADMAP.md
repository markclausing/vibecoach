# VibeCoach Roadmap

**Live plan:** open & active work. Completed epics (full history) → **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**. This file deliberately stays short so it is cheap to load as context (for humans and AI agents alike); detail on completed work lives in the archive.

Legend: ✅ done · 🔄 active · ⏳ backlog

---

## Open work (at a glance)

| Epic | What it is | Pickup trigger |
|---|---|---|
| ⏳ **#62** | Remaining user-feedback hardening: form validation, permission visibility, sync edge paths, strict concurrency | a concrete unhappy flow, or before a Swift 6 upgrade |
| ⏳ **CI backlog (#46)** | TestFlight deploy, snapshot tests, dependency scan, perf checks, concurrency matrix, release-please | each item has its own trigger (first release, UI regression…) |
| ⏳ **#59** | Strava Developer Program compliance: base-URL change (June 2027), check AI-data terms | approaching Strava deadlines |
| ⏳ **idea** | Mental benefit of workouts (not yet worked out) | more "why am I training this" context wanted |

---

## Active & planned

### ⏳ Epic #62: Remaining user-feedback hardening — forms, permissions & concurrency

Consolidation of the open stories that were left hanging in two otherwise-completed epics: the undelivered hardening groups from **Epic #51** (error messages, validation & visibility) and the optional build-setting promotion from **Epic #39** (Swift 6 strict concurrency). All still relevant — they are unhappy-flow gaps that clash with the Management-by-Exception principle — but none of them is blocking; that's why they were detached from their original epic and bundled here as one forward-looking goal. Full scope + acceptance criteria of the #51 stories are in [issue #265](https://github.com/markclausing/vibecoach/issues/265).

**Stories** (each its own PR):

* **⏳ 62.1 — Create & manage goals (was 51.B):** enforce a goal date at least +7 days out, realistic stretch times per sport, title trim on save, and soft-delete so a removed goal leaves no stale coach context behind.
* **⏳ 62.2 — AI provider & API key (was 51.D):** auto-trim whitespace on paste, prefix detection that warns about a key from the wrong provider (e.g. `sk-` under Gemini), and test-key feedback that persists across a provider switch or app restart.
* **⏳ 62.3 — Onboarding & permissions (was 51.E):** HealthKit as a required step (not silently skippable), notifications explicitly optional, a status banner when a permission was skipped, detection of access revoked after the fact, and a permission-status overview in Settings.
* **⏳ 62.4 — Data sync — remaining paths (was 51.F3/F4/F6):** HealthKit per-type permission handling, making a weather error non-blocking with a retry marker instead of a hard interruption, and captive-portal detection (online but behind a login portal).
* **⏳ 62.5 — Proactive coach (background) (was 51.G):** a status row in Settings showing whether Engine A/B is running, a notification-permission pre-check before registration, and visibility of a registration error instead of a silent failure.
* **⏳ 62.6 — Strict Concurrency Checking → `Complete` (was 39.3):** promote the project build setting so new Sendable/actor-isolation regressions become hard compile errors instead of warnings. New warnings may surface that have to be resolved first; hence a separate PR once the codebase has been stable for a while. Builds on CI-backlog story 46.B5 (concurrency-strict build as a matrix cell).

**Pickup trigger:** a concrete unhappy flow that hits a user (a goal with a date in the past, a wrongly pasted key, or confusion about which permissions are active), or the wish to enforce concurrency discipline before a Swift 6 upgrade.

**Suggested order:** start with 62.1 + 62.2 (form validation, smallest surface, direct user benefit), then 62.3 + 62.5 (permission visibility), then 62.4 (sync edge paths), and 62.6 as a standalone concurrency PR whenever it suits.

---

### ⏳ CI backlog (from Epic #46): pipeline extensions

Six deliberately-deferred CI extensions from the completed **Epic #46** — no commitment, each with its own pickup trigger. Full rationale per item is in the [archive (Epic #46)](ROADMAP-archive.md).

* **⏳ 46.B1 — TestFlight deploy** on merge to main (requires an Apple Developer account + App Store Connect API key + signing certs in GitHub Secrets). Trigger: automating the TestFlight flow instead of manually uploading an archive.
* **⏳ 46.B2 — Snapshot tests** (`swift-snapshot-testing`, PNG diff on Dashboard/Goals/Chat/Settings). Trigger: a UI regression the XCUITests missed.
* **⏳ 46.B3 — Dependency vulnerability scan** (`dependency-review-action` on `Package.*`). Trigger: active SPM use for third-party deps.
* **⏳ 46.B4 — Performance regression checks** (build-time tracking + a light `XCTMetric` baseline). Trigger: reported slowness + a need for objective baselines.
* **⏳ 46.B5 — Concurrency-strict build as a matrix cell** (`SWIFT_STRICT_CONCURRENCY=complete`). Trigger: once Epic #62 story 62.6 is done — builds on it.
* **⏳ 46.B6 — Semver via `release-please`** + git-tag-based `MARKETING_VERSION`. Trigger: first real release (TestFlight/App Store).

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
