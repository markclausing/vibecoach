# VibeCoach Roadmap

**Live plan:** open & active work. Completed epics (full history) → **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**. This file deliberately stays short so it is cheap to load as context (for humans and AI agents alike); detail on completed work lives in the archive.

Legend: ✅ done · 🔄 active · ⏳ backlog

---

## Open work (at a glance)

| Epic | What it is | Pickup trigger |
|---|---|---|
| ⏳ **#63** | CI pipeline extensions — TestFlight deploy (63.1, **maintainer wants this**), concurrency baseline guard (63.5), snapshot tests + dep scan (63.2+63.3 coupled) | 63.1: as soon as the maintainer's App Store Connect prerequisites are in place; others per-story |
| ⏳ **#69** | Mental benefit of workouts — subjective track first (existing rpe/mood check-in data) | more "why am I training this" context wanted |
| ⏳ **#70** | Per-workout chat with local memory — inline "discuss this workout" section, distilled facts feed plans & feedback | wanting to tell the coach *about* a specific workout (feel, route, day condition) |
| ⏳ **#59** | Strava Developer Program compliance: base-URL refactor (59.1 anytime) + flip (June 2027), terms verification | Strava migration docs appearing / early 2027; 59.1 fits any quiet moment |
| ⏳ **#68** | Oversized-file splits: 5 files above the 600-LOC lint cap (residual from archived Epic #64) | next time one of the listed files is opened for other work |

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

### ⏳ Epic #70: Per-workout chat with local memory ("discuss this workout")

Maintainer goal (July 2026): a small chat input on the workout detail page where the user can talk *about that workout* — how it felt, the route, whatever — plus their condition that day/week. The app remembers this locally and feeds it into plans and feedback. Guardrails keep the chat strictly on-topic (this workout + the user's current condition).

**Design decisions (maintainer, July 2026):** **hybrid persistence** — the full chat thread is stored per workout (re-readable when reopening the detail page) *and* the coach distils compact facts out of it for prompt context; **inline section** at the bottom of `WorkoutAnalysisView` (no sheet, no tab hand-off); facts are visible/deletable **at the workout itself only** (no Settings surface).

**Grounding (existing building blocks — most of this epic is composition, not invention):**

- **Guardrail pattern:** `ChatScopeInstruction` (Epic #51-A1) — a pure-Swift scope constant prepended to the systemInstruction, unit-testable. The workout chat gets a *narrower* sibling.
- **Memory pattern:** the coach already proposes durable facts via structured JSON (`detectedPrefs` → `UserPreference` inserts with containment-dedupe, `ChatView.swift` ~553). Same extraction pattern, new target model.
- **Chat plumbing:** `GenerativeModelProtocol` + `AIModelFactory` (BYOK, provider-agnostic), `ChatConversationTrimmer`, `ChatInputValidator`, `PromptInputSanitizer` — all reusable as-is.
- **Prompt assembly:** `CoachPromptAssembler` + pure per-block formatters (`LastWorkoutContextFormatter`, `SymptomContextFormatter`, …) — the fact block becomes one more formatter.
- **Not persisted today:** main-chat `ChatMessage` is a plain struct — per-workout persistence needs new `@Model`s → **SchemaV7 migration (§2.1 applies in full)**.

**Stories:**

* **⏳ 70.1 — SchemaV7: two local-only `@Model`s + migration.** `WorkoutChatEntry` (id, `activityID: String` keyed to `ActivityRecord.id` by value, role rawValue, text, timestamp) and `WorkoutChatFact` (id, activityID, factText, `category: WorkoutFactCategory` — type-safe enum per §2, e.g. `.feel` / `.route` / `.dayCondition`, createdAt). One type per file (§5). Pure addition → §2.1 protocol anyway: snapshot `SchemaV7`, `MigrationStage.lightweight`, bump `makeModelContainer()`, and a file-backed `SchemaMigrationV6ToV7Tests` asserting `FitnessGoal`/`UserPreference` survival + writability of the new models. **Data-loss class:** both are local-only (like `Symptom`) — §12 fallback wipes them on a failed migration; accepted, which is exactly why the migration test is mandatory.
* **⏳ 70.2 — `WorkoutChatScopeInstruction` guardrail (pure Swift).** Sibling of `ChatScopeInstruction`, but narrower: only (a) *this* workout (name/date/type/metrics interpolated into the instruction) and (b) the user's physical/mental condition that day/week (sleep, stress, energy, niggles). Everything else — including general training questions that belong in the Coach tab — gets the redirect template, phrased in the user's language, pointing to the Coach tab where appropriate. Unit tests: instruction content, interpolation, both scope branches described.
* **⏳ 70.3 — `WorkoutChatViewModel` + fact distillation.** A slim view model (injected `GenerativeModelProtocol` per §6 — no AppStorage) that loads/saves the thread for one `activityID`, assembles the prompt (70.2 instruction + workout data block + active `WorkoutChatFact`s + recent `Symptom`s), and extends the structured-JSON response contract with a `workoutFacts` array (mirror of `detectedPrefs`): each entry `{text, category}` → insert as `WorkoutChatFact` with the existing containment-dedupe. Distillation guidance lives in the systemInstruction: distil only *durable, plan-relevant* facts (feel vs. load, route quality, day-condition causes) — not chit-chat. Unit tests: parser round-trip, dedupe, category mapping (unknown category → dropped, §2 front-door rule).
* **⏳ 70.4 — Inline chat UI on the workout detail page.** A "Discuss this workout" section at the bottom of `WorkoutAnalysisView`: persisted thread (last few messages + expand), input field (reusing `ChatInputValidator` limits), and the distilled facts rendered as small deletable chips ("remembered: *route beviel goed*" ✕) — the only management surface, per the maintainer's choice. New component files under `Views/WorkoutAnalysis/` (the host view is 416 LOC — the section must not push it over the §5 cap; `WorkoutChatSection.swift` as its own file, registered per §9). All new strings hand-added to `Localizable.xcstrings` (NL + EN/DE/ES) + `normalize-xcstrings.swift` (§13). Logging of chat text/facts only with `privacy: .private` (§11).
* **⏳ 70.5 — Coach-context integration ("use it in plans and feedback").** New pure formatter `WorkoutFactsContextFormatter` emitting a `[WORKOUT NOTES]` structural marker block, + the matching section description in the `systemInstruction` reference — **both sides in the same PR, grep both (§13)**. Injection policy: facts from the trailing 14 days (Calendar math, §3), `.dayCondition` facts of the current week weighted first, capped (e.g. max 20, newest first) to bound prompt size. Consumed by the main coach chat *and* the recovery-plan prompt. Optional follow-up (not committed): feed a workout's own facts into its `WorkoutInsightService` narrative — requires adding a fact-hash to the `WorkoutInsightCache` fingerprint so stored insights invalidate when facts change.

**Architecture artefacts:** `WorkoutChatEntry`/`WorkoutChatFact` (@Models), `WorkoutChatViewModel`, `WorkoutFactsContextFormatter`, `WorkoutChatSection` are building blocks → `architecture.json` + `architecture.html` in the same PR (§7 hard trigger); ARCHITECTURE.md gains a section (new memory/persistence concept). **README showcase:** this significantly extends the `04-workout-deepdive` surface → feature-block copy update + an explicit maintainer screenshot task in the PR body (§7 showcase trigger).

**Effort estimate:** ~2–3 days (70.1 ~2h · 70.2 ~1–2h · 70.3 ~4–6h · 70.4 ~4–6h · 70.5 ~2–3h, plus docs/i18n).

**Suggested order:** 70.1 → 70.2+70.3 → 70.4 → 70.5 (each PR-able on its own; 70.4 is the first user-visible step, 70.5 closes the loop into plans/feedback).

**Pickup trigger:** wanting to tell the coach something about a specific workout that the sensors can't know (feel, route, context of the day). Pairs naturally with Epic #69 (both enrich the subjective layer), but has no dependency on it.

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

Residual from archived **Epic #64**: five files still sit above the 600-LOC SwiftLint warning cap (§5) and carry a `// swiftlint:disable file_length` header (debt visible at the point of debt). Splitting is opportunistic — never a sprint, no functional change ever.

| File | LOC (July 2026) | Natural split seam |
|---|---|---|
| `Views/DashboardView.swift` | 882 | remaining inline card/section subviews → `Views/Dashboard/` (the 64.1 pattern) |
| `Views/SettingsView.swift` | 703 | next cohesive `Section` blocks → `Views/Settings/` (the 64.2 pattern) |
| `Views/ChatView.swift` | 680 | coach-card subviews / input-bar components into own files |
| `Views/GoalsListView.swift` | 640 | goal-row + phase-disclosure components |
| `Services/Sync/HealthKitManager.swift` | 607 | sample-query builders vs. authorization/background-delivery plumbing |

**Rules per split (all established, §5/§9):** each split its own `chore/` PR; pure file-split — type names identical, so SwiftData and callers notice nothing; remove the `swiftlint:disable` header once the file drops under the cap; new files registered in `project.pbxproj` per §9; no `architecture.json` change unless a split promotes a type into a genuine building block. On-device validation = smoke test that the affected screen still renders.

**Pickup trigger:** next time one of the listed files is opened for other work — do the split first (or immediately after) in its own PR.

---

## Recently completed (last 5)

- ✅ **#64** Refactor-review follow-ups — DashboardView/SettingsView splits, stale-marker cleanup; residual oversized files → Epic #68
- ✅ **#67** "How it's built" viewer — visual dev-workflow (agent collaboration, CI pipeline, branching, docs) in the architecture HTML
- ✅ **#66** Architecture-viewer redesign — mobile-first + non-programmer progressive disclosure (Story → Map → Depth)
- ✅ **#65** Refactor-review follow-ups — ChatViewModel split, bounded queries, sync-orchestration extraction, lint guardrails
- ✅ **#62** Remaining user-feedback hardening — forms, permissions & concurrency

Full history (Phases 1–9 + all completed epics) is in **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**.
