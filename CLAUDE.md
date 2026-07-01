# VibeCoach — Architecture & Development Rules for Claude

This file contains the fixed project instructions for the AI assistant (Claude).
Read it at the start of every session as the basis for all decisions.

---

## 0. Meta: Autonomous Context Management

**Proactive updates:** Claude is responsible for keeping **all four project doc files** up to date (`README.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`). On a new architectural choice, a structurally fixed bug (e.g. an iOS quirk), or a new project standard: update the right file directly without asking permission. See §7 for the scope split per file.

**Token optimisation (the cache):** when there is a lot of back-and-forth about a complex concept, Claude summarises the final conclusion, adds it as a hard rule, and reports: *"I've updated the rules. You can type `/compact` now to save tokens."*

**Epic transitions:** at the start of a new Epic, Claude checks all doc files for stale or irrelevant rules that can be removed to keep the cache clean.

---

## 1. Product Philosophy: Management by Exception

- The app does **not** warn on good behaviour — only on deviations (training too hard or too light).
- A 'red status' in the Dashboard **must always** be accompanied by an AI-generated recovery plan (Action Phase). Showing it without a solution is not enough.
- Proactive notifications are targeted: Engine A reacts to action (new workout), Engine B to inaction (sitting still).

---

## 2. Data model: SwiftData Strictness

- **Never** use raw strings for categories. Type-safe enums only, e.g. `SportCategory: String, Codable`.
- When importing from external sources (HealthKit, Strava), raw data is mapped to these enums **right at the front door** — before it reaches SwiftData.
- Do not add new `@Model` classes without a corresponding migration consideration.

### 2.1 Schema migration protocol

**Mandatory for every `@Model` change — including pure additions** (May 2026 incident: Epic #49 added two optional fields to `ActivityRecord` without a schema bump; SwiftData's lightweight inference behaves differently with an explicit `migrationPlan` and the container init failed → the fallback wiped `FitnessGoal` + `UserPreference` local-only data). No more exceptions for "pure additions".

1. **Snapshot the old schema** in `Models/SchemaV<N>.swift` as `enum SchemaV<N>: VersionedSchema`. Nested `@Model` types keep the **same unqualified name** as the live types (e.g. `SchemaV1.Symptom` — not `V1Symptom`) so the SwiftData entity name matches what is in the existing store. Mismatched entity names break the migration with "Cannot use staged migration with an unknown model version". Earlier-version schemas that already reference the changed type must also be updated — point them at the snapshot of the most recent unchanged version (e.g. `SchemaV1.models` points at `SchemaV2.ActivityRecord.self` if V1 → V2 was a no-op for ActivityRecord).
2. Add a new `MigrationStage` to `AppMigrationPlan`. For **pure additions**, `MigrationStage.lightweight(fromVersion:toVersion:)` is sufficient. Schemas that stay unchanged (e.g. `FitnessGoal`) are referenced directly in both schemas — not snapshotted.
3. **Type changes** (e.g. `String` → enum): capture-in-`willMigrate` + restore-in-`didMigrate`. `@Attribute(originalName:)` alone can handle a rename that preserves the type, not an implicit type conversion to a RawRepresentable enum.
4. **New unique constraints on a populated field**: dedupe in `willMigrate` before the schema flip — otherwise applying the constraint fails hard with a SQLite violation.
5. **Bump the container init in `AIFitnessCoachApp.makeModelContainer()`** to the new `SchemaV<M>.models` so the migration plan is actually exercised.
6. Always write a `SchemaMigrationV<N>To<M>Tests` with a **file-backed** seed store as a happy-path safety net. In-memory stores do not work for migration paths (there is no V<N> store file to start from). Test at least (1) that `FitnessGoal` + `UserPreference` records survive the migration (local-only loss risk) and (2) that new fields are writable after migration.

---

## 3. Time & Date Logic

- **Never** use `TimeInterval` math (multiplying seconds) to compute periods in the past.
- **Always** use `Calendar.current.date(byAdding:to:)` for time filters — this avoids bugs with daylight saving time and leap years.
- Base-building (historical data for burndown) is always computed from `Date()` (today), **not** from `targetDate` in the future.

---

## 4. Background Processes: Dual Engine Architecture

- **Engine A (Action Trigger):** `HKObserverQuery` + `enableBackgroundDelivery` — the app wakes on every new HealthKit workout and immediately checks the burndown deviation.
- **Engine B (Inaction Trigger):** `BGAppRefreshTask` via `BGTaskScheduler` — a daily silent background check whether the user has been inactive too long while a goal is in the red.
- The `ProactiveNotificationService` (singleton) manages both engines. Risk data is cached in `UserDefaults` from `DashboardView` (on `onAppear` + after refresh).
- Cooldown: at most 1 proactive notification per goal per 24 hours.

---

## 5. SwiftUI & iOS Style Rules

- Modular code: split large screens into smaller reusable components.
- **One top-level type per file.** Mandatory for `@Model` classes; for structs/enums only combine them when they are tightly coupled (e.g. an enum + its supporting structs like `BodyArea` + `Symptom`).
- **Soft cap: ±500 LOC per Swift file.** If it goes over, split by logical responsibility (model class, prompt formatter, query helper, etc.). Pure file splits without semantic changes are always safe — type names stay identical, so SwiftData and callers notice nothing.
- Use standard iOS components — simple, modern and native.
- Explain complex logic (API integrations, background processes) via comments **in English**.
- Build step by step: basics first, complex features later.

---

## 6. Testing Policy

### What TO test
- **Pure-Swift logic** in `Services/`, `Models/`, `ViewModels/` helpers: classifiers, calculators, formatters, schedulers. Highest ROI — easy to test, catches regressions early.
- **Schema migrations** (see §2.1): file-backed seed-store tests mandatory. In-memory stores do not work for migration paths.
- **Domain rules with edge cases:** HR-zone boundaries, injury-keyword detection, DST transitions, dedupe heuristics, threshold detection. This is where the subtle bugs live.
- **Happy-path UI flows** via XCUITest: onboarding, navigation to each tab, creating a goal. Nothing more than that.

### What NOT to test
- Trivial getters/setters or SwiftData boilerplate. No value, only maintenance burden.
- View-layer orchestration without a clean injection seam (concurrent sync, `async let` flows in `performAutoSync`). Document instead of test, in the PR checklist + on-device validation.
- iOS-framework things that do not work in the simulator sandbox (Keychain entitlements, BGTaskScheduler timing).

### Safeguarding testability
- **Keep pure-Swift helpers free of AppStorage/UserDefaults.** The caller injects state via parameters. Examples: `ActivityDeduplicator`, `SessionClassifier`, `WorkoutPatternDetector`, `PhysiologicalThresholdEstimator`. A helper that reads `@AppStorage` is a testing nightmare and a main-actor isolation problem in one.
- **Mocking for UI tests** via `UITestMockEnvironment.setup()` (gated on the `-UITesting` launch argument + `#if DEBUG`). Writes a dummy API key, weather data, periodisation context so views render without live API calls. `UITestMockGenerativeModel` replaces the Gemini call with a hardcoded JSON response.
- **Test-only bypasses** in production code are only allowed behind a `-UITesting` check + a comment explaining why (see `ChatView`'s `hasAPIKey` gate as an example).

### CI discipline (learned via Epic 46.4)
- **UI tests run sequentially on CI** (`-parallel-testing-enabled NO`). Parallel clones trigger `ipc/mig server died` on GitHub `macos-latest` runners. Locally the scheme config stays parallel for speed.
- **On UI-test failures on CI, inspect the xcresult bundle first** via `xcrun xcresulttool get test-results activities --test-id <id>`, before blaming runner flakiness. Test-code bugs (hidden NavigationBar in V2.0, `.textField` lookup for SwiftUI's `.textView` rendering, too-short timeouts) are more often the cause than real runner issues.
- **Coverage is signal, not a KPI.** The `coverage-report` job generates per-directory + combined aggregates. Aim for high coverage on `Services/` + `Models/` + `ViewModels/` (testable code); `Views/` stays limited by SwiftUI testability and is reported separately.

---

## 7. Documentation Discipline

Four files together carry the project state. Each has its own scope; **no overlap, no duplication**.

### Split

| File | Scope | Who reads it | Rule of thumb for length |
|---|---|---|---|
| **`README.md`** | Product showcase (what is this + what it does for you + how to build it) on top, then a short technical summary that points to the info | New reader / GitHub visitor / potential user | Showcase may be long, but the **technical-summary block** ("Under the hood": status, stack, CI, recently-completed) stays < 1 screen — detail stays in ROADMAP/ARCHITECTURE |
| **`docs/ROADMAP.md`** | **Live plan only:** the "Open work" index (one row per open epic + pickup-trigger) + active/planned epics (🔄 / ⏳) + a short "Recently completed" pointer list. Completed epics move out to the archive. | Whoever (human or AI agent) wants a cheap, current "what's open" view | Keep it lean — open work + index; no full ✅-history here |
| **`docs/ROADMAP-archive.md`** | Full history of completed (✅) epics, original order, append-only | Whoever digs into "why/when was X built" | Read on demand; grows over time |
| **`docs/ARCHITECTURE.md`** | Per architecture layer, explaining "how does this work and why" | Whoever wants to understand the code and the reasons behind choices | A section per concept with code pointers |
| **`CLAUDE.md`** | Fixed rules & patterns for working on this codebase | AI assistant + new collaborators | Stable; only update when a rule changes |

### Update protocol on new functionality

Every PR that adds functionality **must** update all relevant files — not just one of the four:

- **`README.md`** — touch it only if the feature is significant enough to warrant a **showcase feature block** (screenshot slot in `docs/screenshots/` + a "what you get" benefit line) or it changes the short "Under the hood" technical summary / "Recently completed" line. Keep the technical summary terse; don't let the showcase drift into ROADMAP-level detail. Otherwise: leave it alone (prevents the overview from going stale).
- **`docs/ROADMAP.md`** — Epic status ⏳ → 🔄 → ✅, tick off sub-stories, update the "Effort realised" + "Status" line. When starting a new Epic: add it to the "Open work" index + an "Active & planned" section with rationale + sub-stories. **When an Epic is fully ✅: move its block to `docs/ROADMAP-archive.md` (keep original order), drop its "Open work" index row, and add a one-line entry under "Recently completed".** This keeps the live ROADMAP cheap to load as context for humans and AI agents.
- **`docs/ARCHITECTURE.md`** — if the feature introduces a new architectural choice (new service layer, sync pipeline, security pattern) or changes an existing section. Pure refactors without an architectural change need nothing here.
- **`CLAUDE.md`** — only if the feature establishes a new permanent pattern (testing policy, date handling, logger discipline). One-off Epic work does not belong here — that goes in the ROADMAP.

### Definition of Done — doc checklist (BLOCKING, every feature/epic PR)

Docs are part of the change, not a follow-up. Before a feature/epic PR is opened **and again before its final commit**, walk this checklist explicitly — in the PR body's test plan, tick what applies and state "n/a" for the rest, so a skipped item is a visible decision, not an oversight:

- [ ] **ROADMAP status flipped.** The PR *is* the merge (squash & merge follows immediately), so set the Epic heading **and every implemented story** to ✅ in this PR — never leave merged work at 🔄/⏳. Add the `**Merged via PR #N. Effort:** …` closing line. (Use the PR number; if not yet known, add it in the final commit.) Add the next logical ⏳ goal if the epic opens one. **When the Epic is fully ✅, move its block to `docs/ROADMAP-archive.md` and update the live "Open work" index + "Recently completed"** (see the ROADMAP / ROADMAP-archive split in the §7 table).
- [ ] **architecture.json + .html synced** — see the hard trigger below. This is the single most-forgotten item; check it every time.
- [ ] **ARCHITECTURE.md** — new section (or edit) if an architectural concept was introduced; else n/a.
- [ ] **README.md** — only if core-features or the "Recently completed" line is affected, **or a showcase view changed / a significant user-facing view was added** (see the showcase trigger below); else n/a.
- [ ] **CLAUDE.md** — only if a new permanent pattern was established; else n/a.
- [ ] **i18n catalog entries** — every new user-facing string added in this PR has a `Localizable.xcstrings` key (NL source + EN/DE/ES) + `normalize-xcstrings.swift` run; else n/a. Extraction is off (§13), so a missing entry ships Dutch verbatim in EN/DE/ES and the unit suite won't catch it.

### Hard trigger for the derived artefacts

**If this PR added, removed, or renamed any top-level type in `AIFitnessCoach/` that is a building block** — a `Service`, `@Model`, SwiftUI `View`, ViewModel/`formatter`, `parser`, `store`, `calculator`/pure helper, `validator`, migration, or external client — **then `architecture.json` + `architecture.html` MUST change in the same PR.** No exceptions, even for a type added to an existing file (Epic #60's `PhaseTimeline`/`PhaseWindowCalculator` lived in one new file; `ProgressService` had existed for many epics yet was never registered — both are exactly the drift this rule prevents). Follow the 5 steps under "Architecture visualisation" below. Pure refactors with no new/removed building block (rename within a file, force-unwrap fix, logger cleanup) are exempt.

**Quick self-audit when in doubt or at epic close:** list the top-level type declarations you touched and confirm each building-block type has a matching `id` in `architecture.json` (`grep '"id":' docs/architecture/architecture.json`). A missing entry = drift to fix now.

### Hard trigger for the README showcase (Epic #58)

The root `README.md` is a **product showcase**: a hero + eight feature blocks, each backed by a screenshot in `docs/screenshots/`. These blocks map to specific views:

| Screenshot slot | View / surface |
|---|---|
| `00-hero` | Dashboard (full screen) |
| `01-vibe-score` | Vibe Score card (`VibeScoreCardV2`) |
| `02-proactive-coaching` | Proactive notification / red banner + recovery plan |
| `03-coach-chat` | Coach tab (chat) |
| `04-workout-deepdive` | `WorkoutAnalysisView` (annotated chart + pattern chips) |
| `05-goals-phases` | Goals view (phase `DisclosureGroup` / `PhaseMilestonesView`) |
| `06-multiday-weather` | Week schedule with stage entries + per-stage weather |
| `07-dual-source-sync` | Data-source settings / source badge |
| `08-language-privacy` | Settings → language picker |

**If this PR significantly changes the look or behaviour of a view in that table, OR adds a significant new user-facing view/feature, then in the same PR you MUST:**

1. **Update the README** — revise the relevant feature block's copy + "what you get" line, or add a new feature block (+ a new `docs/screenshots/NN-<slug>.png` slot + a row in `docs/screenshots/README.md`) for a new surface.
2. **Remind the maintainer to capture the screenshot.** A screenshot is a **manual on-device capture by the maintainer** — the assistant cannot take it. So in the PR body's test plan add an explicit unchecked maintainer task, e.g. `- [ ] Maintainer: replace docs/screenshots/04-workout-deepdive.png with a fresh capture`, and call it out in the closing message. Never silently leave a stale screenshot next to changed UI, and never substitute a generated/placeholder image for a real capture.

"Significant" = a visible redesign, a new card/section, a renamed/restructured screen, or a brand-new view — not a copy tweak, a colour nudge, or a bugfix with no visual change. When unsure, flag it: a one-line "screenshot may need refreshing" note costs nothing.

### Statuses in the ROADMAP

- ✅ done, merged on `main`
- 🔄 active, branch open or in review
- ⏳ planned or speculative, no commitment yet

Always add the next logical goal so the roadmap looks ahead.

### Pure docs-only PRs

May go directly to `main` (exception to §8). For feature PRs: code + docs in the same commit. Don't artificially split into a code PR + docs PR.

### Architecture visualisation (derived artefacts)

Besides the four source-of-truth files (§7 table) there are two **derived** documents that present the architecture in a clickable and machine-readable form:

| File | Purpose | Source |
|---|---|---|
| **`docs/architecture/architecture.html`** | Interactive viewer for humans — layers, modules, subsystems, flows, clickable dependency graph | Derived from `docs/ARCHITECTURE.md` + codebase |
| **`docs/architecture/architecture.json`** | Machine-readable structure for AI agents — same data, JSON schema | Derived from `docs/ARCHITECTURE.md` + codebase |

**Not source-of-truth.** Both files derive from the codebase + `ARCHITECTURE.md`. On conflicts the codebase wins, then `ARCHITECTURE.md`, then these files. Never add new architecture explanation here only — write it in `ARCHITECTURE.md` first and sync it here.

**Update discipline.** Every PR that touches `ARCHITECTURE.md` or introduces a module-layer change in `AIFitnessCoach/` (new `Service`, new `@Model`, new `@StateObject` in `AIFitnessCoachApp`, new external API, new subsystem/flow) must also include these two files in the same commit:

1. Add/change the module in `architecture.json` (id, layer, kind, file, description, uses, tags).
2. Optionally add an entry to `subsystems` or `flows`.
3. Bump `meta.docRevision` by 1.
4. Set `meta.lastUpdated` to today (ISO `YYYY-MM-DD`).
5. Re-inject the JSON into `architecture.html` via:
   ```sh
   python3 -c "import json; \
     data=open('docs/architecture/architecture.json').read(); \
     json.loads(data); \
     html=open('docs/architecture/architecture.html').read(); \
     import re; \
     new=re.sub(r'(<script id=\"architecture-data\" type=\"application/json\">)([\s\S]*?)(</script>)', lambda m: m.group(1)+chr(10)+data+chr(10)+m.group(3), html); \
     open('docs/architecture/architecture.html','w').write(new)"
   ```

Pure refactors without a structural change (rename within one file, force-unwrap fix, logger cleanup) do not need to touch these files.

**Versioning.** `meta.appVersion` matches `CFBundleShortVersionString` in `AIFitnessCoach/Info.plist`. On every bump of that plist value, `appVersion` is updated too and `docRevision` is reset to `1`. `docRevision` counts, within one app version, how often the architecture was revised — giving AI agents and code reviewers a clear anchor to see whether a cached picture is still current. `meta.buildNumberSource` records how `CFBundleVersion` itself is determined (git commit count via a Build Phase script) — we do *not* mirror that dynamic number into the docs, otherwise every commit would trigger a doc bump.

---

## 8. Git Workflow

- Every code change goes through a branch + PR — **never directly on `main`**, not even for small fixes. Exception: pure README/backlog updates (docs-only).
- Branch-name conventions per type of change:
  - `feature/epic-{nr}-{short-description}` — new epics/sprints (e.g. `feature/epic-13-proactive-coaching-engine`)
  - `fix/{short-description}` — regular bugfixes (e.g. `fix/vibe-score-nil-crash`)
  - `hotfix/{short-description}` — production-critical, fast-track merge
  - `security/{alert-id-or-description}` — security fixes (e.g. `security/codeql-dob-logging`)
  - `ci/{short-description}` — workflow/pipeline changes
  - `chore/{short-description}` — tech debt, cleanup, refactors without behaviour change (e.g. `chore/swiftlint-cleanup`)
  - `docs/{short-description}` — pure documentation updates (rarely needed — usually docs belong with a feature PR; see §7)
- Workflow per branch:
  1. Create branch → build code → push
  2. Right after the first push **the assistant automatically creates the PR** via `gh pr create` (title from the branch name, body with `## Summary` + `## Test plan` checklist per the Claude Code default). Don't ask for separate approval — the PR is a conduit, not a merge action.
  3. The user pulls and tests (for feature branches, on device)
  4. Feedback → make fixes on the **same** branch (push updates the existing PR automatically)
  5. Satisfied → the user does a **squash & merge** to main (the assistant does not merge)
  6. After a merge / at the start of the next sprint: delete merged branches locally and remote **and verify the docs landed** — the merged Epic + its stories show ✅ in `docs/ROADMAP.md`, and any new building-block type is registered in `architecture.json` (§7 Definition-of-Done). Fix drift immediately via a docs-only commit to `main` (allowed, §7); don't defer it.
- PR discipline:
  - **One fix per PR** — no piggybacked refactors or "while-I-was-at-it" changes
  - Always link the source in the PR description: CodeQL alert ID, issue number, crash report, or user report
  - Add a regression test where feasible (per §6)
- Security fixes specifically:
  - Public CodeQL alerts → the regular `security/` branch + PR flow is sufficient
  - Real exploitable vulnerabilities in production → use a **private GitHub Security Advisory** + private fork, publish only after the fix

### 8.1 Conventional Commits (load-bearing for release automation — Epic #63 story 63.6)

`release-please` (`.github/workflows/release-please.yml`) derives the next semver bump and the changelog from commit messages, so commit subjects **must** follow [Conventional Commits](https://www.conventionalcommits.org/):

- `type(optional-scope): summary` — e.g. `feat: per-stage weather`, `fix: vibe-score nil crash`, `docs: translate ROADMAP`.
- **Releasing types:** `fix:` → patch, `feat:` → minor, `feat!:` / `fix!:` / a `BREAKING CHANGE:` footer → major.
- **Non-releasing types** (no version bump, still valid): `docs:` · `chore:` · `ci:` · `test:` · `refactor:` · `build:` · `perf:` · `style:`.
- **Because we squash & merge (§8 step 5), the PR _title_ becomes the single commit subject on `main`** — so the **PR title** is what release-please parses. Always give the PR a valid Conventional-Commit title; the per-commit subjects on the branch matter less once squashed. This is already the de-facto style here — 63.6 just makes it load-bearing, so a malformed subject silently misses a release bump.

### 8.2 How a release is cut (in practice)

Two version numbers move on different clocks (see `docs/ARCHITECTURE.md#11`):

- **Build number** (`CFBundleVersion`) — auto-increments **every commit** (`git rev-list --count HEAD`, Build Phase). Never touched by hand.
- **Marketing version** (`CFBundleShortVersionString`, semver) — moves **only when a release is cut**, in two stages:

1. **Proposed continuously (automatic).** Each push to `main` re-runs `release-please`, which keeps a rolling **Release PR** (`chore(main): release X.Y.Z`) up to date — accumulating the changelog and recomputing the next version from the Conventional-Commit titles since the last release. Nothing is released yet; it is a standing proposal that grows.
2. **Cut the release (manual, maintainer).** **Merge the Release PR.** That creates the git tag `vX.Y.Z` + a GitHub Release with the changelog. From then on, builds stamp `X.Y.Z` as the marketing version (the Build Phase reads `git describe --tags`).

So: merge feature PRs whenever; they pile into one Release PR. The version only goes up — and by how much (the highest of patch/minor/major among the collected commits) — at the moment **you** merge that Release PR. If only non-releasing commits (`docs:`/`chore:`/`ci:`/…) landed, release-please opens no Release PR and the version stays put.

---

## 9. Xcode Project Management (`project.pbxproj`)

- The `skip-worktree` flag is on by default for `AIFitnessCoach.xcodeproj/project.pbxproj`. Git therefore ignores changes to this file.
- When creating a **new Swift file** outside Xcode (via a code editor or AI tooling), the file must also be added to the Xcode build target in `project.pbxproj`. This goes as follows:
  1. Add `PBXFileReference`, `PBXBuildFile` and the reference in the `PBXGroup` + `PBXSourcesBuildPhase` to `project.pbxproj`
  2. Temporarily turn off the skip-worktree flag: `git update-index --no-skip-worktree AIFitnessCoach.xcodeproj/project.pbxproj`
  3. Stage and commit the file
  4. Turn the flag back on: `git update-index --skip-worktree AIFitnessCoach.xcodeproj/project.pbxproj`
- Never forget this step — a file that is not in the project will make the CI build fail with `cannot find 'X' in scope`.

---

## 10. Communication

- Reply to the user **in Dutch** (the maintainer's working language), unless the user explicitly asks for English.
- **Code, code comments and documentation are in English** (see §5 and §7). Code variables and function names follow English Swift conventions.
- Be concise — no unnecessary summaries at the end of a reply.

---

## 11. Logger & Privacy Discipline

- **Never** use `print()` in `Services/`, `Models/` or `ViewModels/`. Replace it with `AppLoggers.<category>.<level>(...)` (see `Services/AppLoggers.swift` for the existing categories — add a new one if the service falls outside the scope of an existing one).
- Privacy modifiers are **mandatory** for anything that can contain user data. Without a modifier `Logger` defaults to `.private`, but make it explicit so code review is clear:
  - `privacy: .private` for HRV, sleep minutes, TRIMP, age, goal titles, workout UUIDs, tokens, RPE/mood, bodyArea raw values
  - `privacy: .public` only for framework error codes (e.g. `error.localizedDescription` of iOS frameworks), counters (`count, weeks`), and non-identifying status flags (auth-status enums, sport raw values)
- In `Views/`, `print()` is allowed as a debug aid, but remove them before commit. CI builds have no lint rule for this — your own responsibility.
- No loose `static let logger = Logger(...)` per service. Centralise in `AppLoggers` — there used to be three duplicates that got out of hand.

---

## 12. Defensive App Init

- Code on the critical launch path (`ModelContainer` init, Keychain migrations, `BGTaskScheduler.register`, filesystem bootstraps) **never** uses `fatalError` as the first catch.
- Pattern:
  1. First attempt: do it normally.
  2. On failure: log via `AppLoggers.<x>.error` with `privacy: .public` on the framework error, and do a **fallback** (remove corrupt state, use defaults, build an empty store).
  3. Only on the second failure: `fatalError`. At that point something is fundamentally wrong (Application Support broken, schema corrupt) and bricking is correct behaviour.
- Example: see `AIFitnessCoachApp.makeModelContainer()`. On migration failure the fallback removes the corrupt SQLite store + WAL/SHM sidecars and builds an empty V<latest> container, with a UserDefaults flag (`vibecoach_migrationFallbackAt`) as a hook for a future UI message.
- HK + Strava data is always re-syncable via `TriggerAutoSync` once the app reopens; only `Symptom` and `UserPreference` are local-only. Accept that data-loss risk over a bricked app — an empty DB is restored in seconds, a crash loop is not recoverable without a reinstall.

---

## 13. Internationalisation (i18n) — Epic #37

The app is multilingual (NL/EN/DE/ES). The codebase, comments and coach prompt are English; only translations and the coach's output language vary. See `docs/ARCHITECTURE.md` §13 for the full picture. Working rules:

- **One source of truth for language:** `AppLanguage` (`Localization/AppLanguage.swift`), backed by `@AppStorage` key `vibecoach_appLanguage`. Views read it via `.environment(\.locale, …)`; pure-Swift code reads `AppLanguage.currentLocale` / `currentPromptLanguageName`. Never read `AppleLanguages` or `Locale.current` directly for app-language decisions.
- **UI strings live in `Localizable.xcstrings`.** `Text("literal")` and `Text("literal \(interp)")` localise *only if the key is in the catalog*. `Text(stringVariable)` / `Text(func())` render **verbatim** — for those:
  - shared row/card components with a `String` param → `Text(LocalizedStringKey(param))`;
  - computed `-> String` UI props → wrap returns in `String(localized:)`.
- **Automatic extraction is OFF (`SWIFT_EMIT_LOC_STRINGS = NO`) — every new user-facing string MUST be hand-added to the catalog in the same PR.** The build does **not** populate `Localizable.xcstrings` from source, so a new `Text("Dutch")` / `String(localized: "Dutch")` literal with no catalog entry renders the **Dutch source verbatim in EN/DE/ES** — a silent regression invisible on a NL device and to the unit suite (locale-agnostic asserts compare `String(localized:)` to itself, so they pass even when the key is missing). It only shows on an EN/DE/ES device. So: when a feature PR adds a user-facing string, author its catalog key (NL source) + EN/DE/ES translations in the **same** PR, then `swift scripts/normalize-xcstrings.swift`, and verify the compiled `.lproj` resolves it. (Epic #62 shipped ~37 untranslated strings exactly because this wasn't enforced; the i18n sweep PRs #328/#331/#333 cleaned them up.)
- **Format keys:** pre-format numbers into a `String` and interpolate as `%@` rather than letting `\(Int)` become `%lld` — a `%lld`-vs-`%@` mismatch between the hand-authored catalog key and the runtime key silently falls back to the source language (only visible on device). `xcodebuild` does not extract keys back to the catalog; author them by hand and verify via the compiled `.lproj`.
- **Prompt vs UI split:** values interpolated into the coach prompt (`SportCategory`/`SessionType.displayName`, `BodyArea.rawValue`/`severityLabel`, `GoalBlueprint.displayName`) stay **Dutch as the prompt term**; localise them only at the View render site via `LocalizedStringKey(value)`. The prompt body is English; output language is steered solely by the `respond in {language}` directive.
- **Date formatting — never `DateFormatter()` inline.** Use `AppDateFormatters` (`Extensions/AppDateFormatters.swift`), which caches formatters and picks the right locale per intent: `display(_:)`/`displayStyle(_:)` for user-facing UI (current app language, rebuilds on language switch), `prompt(_:)`/`promptStyle(_:)` for dates interpolated into the coach prompt (stay `nl_NL`, same rule as the prompt-vs-UI split above), `fixed(_:utc:)` for machine-readable keys / API parsing (`en_US_POSIX`). Inline `DateFormatter()` re-introduces the exact two bugs the helper fixes: a display formatter that forgets `AppLanguage.currentLocale` (Dutch weekday/month verbatim on EN/DE/ES) and a `yyyy-MM-dd` parser that forgets `en_US_POSIX` (latent failure on exotic device locales). Only exceptions: `ISO8601DateFormatter` (different API) and one-off parsers needing a custom `calendar`/`timeZone` the helper doesn't model (e.g. `StravaRateLimitParser`'s HTTP-header `zzz` format).
- **Structural prompt markers** (`[CURRENT COMPLAINTS]`, `🚨 CRITICAL MILESTONE SHORTFALL`, …) must stay identical between every emitter (formatters/services) and the `systemInstruction` reference — renaming one side without the other breaks the coach's section lookup. Grep both sides after any change.
- **Detection logic must be language-independent:** keyword/day-name/activity classification (`injuryKeywords`, `resolvedDate`, `isRestDay`/`kind`) covers NL+EN+DE+ES (+ the duration signal for rest), because the coach now writes `activityType`/dates in the user's language.
- **Tests:** UI tests run forced in `nl` (`-testLanguage nl`). Unit tests asserting localised user-facing output compare against `String(localized:)` of the same key (locale-agnostic), not a hardcoded translation.
- **Catalog formatting — always normalise after a hand-edit.** Xcode saves `Localizable.xcstrings` via Foundation's `JSONSerialization` with `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` (space before the colon, expanded empty objects, keys sorted, slashes/emoji literal). Hand-edits write a compact, unsorted form, so the moment Xcode next touches the file it re-serialises the *entire* catalog → a ~7.5k-line whitespace diff that blocks branch checkouts and pollutes PRs. After every manual edit run `swift scripts/normalize-xcstrings.swift` to restore the canonical format; the diff then stays limited to the keys you actually changed. The script is idempotent and content-preserving (only formatting/order).
