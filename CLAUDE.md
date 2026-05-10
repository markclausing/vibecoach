# VibeCoach — Architectuur & Ontwikkelregels voor Claude

Dit bestand bevat de vaste project-instructies voor de AI-assistent (Claude).
Lees dit bij elke sessie als basis voor alle beslissingen.

---

## 0. Meta: Autonoom Context Management

**Proactieve Updates:** Claude is verantwoordelijk voor het actueel houden van **alle vier project-doc-files** (`README.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`). Bij een nieuwe architectuurkeuze, een structureel opgeloste bug (bijv. een iOS-quirk), of een nieuwe project-standaard: update direct in de juiste file zonder toestemming te vragen. Zie §7 voor de scope-verdeling per file.

**Token Optimalisatie (The Cache):** Als er veel heen-en-weer wordt gepraat over een complex concept, vat Claude de eindconclusie samen, voegt deze toe als harde regel, en meldt: *"Ik heb de regels bijgewerkt. Je kunt nu `/compact` typen om tokens te besparen."*

**Epic Overgangen:** Bij de start van een nieuwe Epic controleert Claude alle doc-files op oude of irrelevante regels die verwijderd kunnen worden om de cache schoon te houden.

---

## 1. Product Filosofie: Management by Exception

- De app waarschuwt **niet** bij goed gedrag — alleen bij afwijkingen (te zwaar of te licht trainen).
- Een 'Rode status' in het Dashboard **moet altijd** vergezeld gaan van een AI-gegenereerd herstelplan (Action Phase). Tonen zonder oplossing is onvoldoende.
- Proactieve notificaties zijn gericht: Engine A reageert op actie (nieuwe workout), Engine B op inactie (stilzitten).

---

## 2. Datamodel: SwiftData Strictness

- Gebruik **nooit** ruwe strings voor categorieën. Uitsluitend type-veilige enums, bijv. `SportCategory: String, Codable`.
- Bij import vanuit externe bronnen (HealthKit, Strava) wordt de ruwe data **direct bij de voordeur** gemapt naar deze enums — vóórdat het in SwiftData belandt.
- Voeg geen nieuwe `@Model` klassen toe zonder bijbehorende migratie-overweging.

### 2.1 Schema-migratie protocol

**Verplicht bij élke `@Model`-wijziging — óók pure additions** (mei 2026 incident: Epic #49 voegde twee optionele velden toe aan `ActivityRecord` zonder schema-bump; SwiftData's lightweight inference werkt anders bij een explicit `migrationPlan` en de container-init faalde → fallback wiste `FitnessGoal` + `UserPreference` lokaal-only data). Geen uitzonderingen meer voor "pure additions".

1. **Snapshot het oude schema** in `Models/SchemaV<N>.swift` als `enum SchemaV<N>: VersionedSchema`. Nested `@Model` types houden **dezelfde unqualified naam** als de live types (bijv. `SchemaV1.Symptom` — niet `V1Symptom`) zodat de SwiftData entity-naam matcht met wat in de bestaande store staat. Mismatchende entity-namen breken de migratie met "Cannot use staged migration with an unknown model version". Eerder-versie-schema's die het gewijzigde type al referenden moeten ook bijgewerkt worden — laat ze verwijzen naar de snapshot van de meest recente onveranderde versie (bijv. `SchemaV1.models` wijst naar `SchemaV2.ActivityRecord.self` als V1 → V2 voor ActivityRecord een no-op was).
2. Voeg een nieuwe `MigrationStage` toe aan `AppMigrationPlan`. Voor **pure additions** is `MigrationStage.lightweight(fromVersion:toVersion:)` voldoende. Schemas die ongewijzigd blijven (bijv. `FitnessGoal`) worden in beide schema's direct gerefereerd — niet ge-snapshot.
3. **Type-changes** (bijv. `String` → enum): capture-in-`willMigrate` + restore-in-`didMigrate`. `@Attribute(originalName:)` alleen kan een rename mét behoud van type aan, géén impliciete type-conversie naar een RawRepresentable-enum.
4. **Nieuwe unique-constraints op vol veld**: dedupe in `willMigrate` vóór de schema-flip — anders faalt de constraint-applicatie hard met een SQLite-violation.
5. **Bump de container-init in `AIFitnessCoachApp.makeModelContainer()`** naar de nieuwe `SchemaV<M>.models` zodat de migration plan ook daadwerkelijk wordt aangesproken.
6. Schrijf altijd een `SchemaMigrationV<N>To<M>Tests` met een **file-backed** seed-store als happy-path-vangnet. In-memory stores werken niet voor migratie-paden (er is geen V<N>-store-bestand om vanaf te starten). Test minstens (1) dat `FitnessGoal` + `UserPreference` records de migratie overleven (lokaal-only verlies-risico) en (2) dat nieuwe velden schrijfbaar zijn na migratie.

---

## 3. Tijd & Datum Logica

- Gebruik **nooit** `TimeInterval`-wiskunde (seconden vermenigvuldigen) om periodes in het verleden te berekenen.
- Gebruik **altijd** `Calendar.current.date(byAdding:to:)` voor tijdsfilters — dit voorkomt bugs met zomertijd en schrikkeljaren.
- Base-building (historische data voor burndown) wordt altijd berekend vanaf `Date()` (vandaag), **niet** vanaf `targetDate` in de toekomst.

---

## 4. Achtergrondprocessen: Dual Engine Architectuur

- **Engine A (Action Trigger):** `HKObserverQuery` + `enableBackgroundDelivery` — de app ontwaakt bij elke nieuwe HealthKit-workout en checkt direct de burndown-afwijking.
- **Engine B (Inaction Trigger):** `BGAppRefreshTask` via `BGTaskScheduler` — dagelijkse stille achtergrondcheck of de gebruiker te lang stilzit en een doel op rood staat.
- De `ProactiveNotificationService` (singleton) beheert beide engines. Risicodata wordt gecached in `UserDefaults` vanuit `DashboardView` (bij `onAppear` + na refresh).
- Cooldown: maximaal 1 proactieve notificatie per doel per 24 uur.

---

## 5. SwiftUI & iOS Stijlregels

- Modulaire code: grote schermen opsplitsen in kleinere herbruikbare components.
- **Eén top-level type per bestand.** Bij `@Model`-classes verplicht; voor structs/enums alleen samenvoegen als ze tightly coupled zijn (bijv. enum + zijn supporting structs zoals `BodyArea` + `Symptom`).
- **Soft cap: ±500 LOC per Swift-bestand.** Komt het erboven, splits per logische verantwoordelijkheid (model-class, prompt-formatter, query-helper, etc.). Pure file-splits zonder semantische wijzigingen zijn altijd veilig — type-namen blijven identiek, dus SwiftData en callers merken niks.
- Gebruik standaard iOS-componenten — simpel, modern en native.
- Complexe logica (API-koppelingen, achtergrondprocessen) uitleggen via comments **in het Nederlands**.
- Bouw stap voor stap: basis eerst, dan pas complexe features.

---

## 6. Testbeleid

### Wat WEL testen
- **Pure-Swift logica** in `Services/`, `Models/`, `ViewModels/`-helpers: classifiers, calculators, formatters, schedulers. Hoogste ROI — gemakkelijk te testen, vangt regressies vroeg.
- **Schema-migraties** (zie §2.1): file-backed seed-store-tests verplicht. In-memory stores werken niet voor migratie-paden.
- **Domeinregels met edge cases:** HR-zone-grenzen, blessure-keyword-detectie, DST-overgangen, dedupe-heuristieken, threshold-detectie. Hier zitten de subtiele bugs.
- **Happy-path UI-flows** via XCUITest: onboarding, navigatie naar elke tab, doel aanmaken. Niet meer dan dat.

### Wat NIET testen
- Triviale getters/setters of SwiftData-boilerplate. Geen waarde, alleen onderhoudslast.
- View-laag-orchestratie zonder clean injection-seam (concurrent sync, `async let`-flows in `performAutoSync`). Document i.p.v. test in PR-checklist + on-device validatie.
- iOS-framework-zaken die in simulator-sandbox niet werken (Keychain entitlements, BGTaskScheduler-timing).

### Testbaarheid borgen
- **Pure-Swift helpers AppStorage-/UserDefaults-vrij houden.** Caller injecteert state via parameters. Voorbeelden: `ActivityDeduplicator`, `SessionClassifier`, `WorkoutPatternDetector`, `PhysiologicalThresholdEstimator`. Een helper die `@AppStorage` leest is een test-nachtmerrie en een main-actor-isolatie-probleem in één.
- **Mocking voor UI-tests** via `UITestMockEnvironment.setup()` (gegated op `-UITesting`-launchArgument + `#if DEBUG`). Schrijft dummy API-key, weersdata, periodisatie-context zodat views renderen zonder live API-calls. `UITestMockGenerativeModel` vervangt de Gemini-call met een hardcoded JSON-response.
- **Test-only bypasses** in productie-code mogen alleen achter `-UITesting`-check + comment die uitlegt waarom (zie `ChatView`'s `hasAPIKey`-gate als voorbeeld).

### CI-discipline (geleerd via Epic 46.4)
- **UI-tests draaien sequentieel op CI** (`-parallel-testing-enabled NO`). Parallel-clones triggeren `ipc/mig server died` op GitHub `macos-latest`-runners. Lokaal blijft scheme-config parallel voor snelheid.
- **Bij UI-test-failures op CI eerst de xcresult-bundle inspecteren** via `xcrun xcresulttool get test-results activities --test-id <id>`, vóór je het op runner-flakiness gooit. Test-code-bugs (verborgen NavigationBar in V2.0, `.textField`-lookup voor SwiftUI's `.textView`-rendering, te-korte timeouts) zijn vaker de oorzaak dan echte runner-issues.
- **Coverage is signal, geen KPI.** De `coverage-report`-job genereert per-directory + combined aggregaten. Streef naar hoge dekking op `Services/` + `Models/` + `ViewModels/` (testable code); `Views/` blijft beperkt door SwiftUI-testbaarheid en wordt apart gerapporteerd.

---

## 7. Documentatie-Discipline

Vier files dragen samen de project-state. Elk heeft een eigen scope; **geen overlap, geen duplicatie**.

### Verdeling

| File | Scope | Wie leest het | Vuistregel voor lengte |
|---|---|---|---|
| **`README.md`** | High-level "wat is dit en waar zit de info" | Nieuwe lezer / GitHub-bezoeker | Huidige Status < 1 scherm |
| **`docs/ROADMAP.md`** | Epic-historie + actieve & geplande stories (✅ / 🔄 / ⏳) + backlog | Wie wil weten "wat hebben we gedaan en wat komt nog" | Per Epic ~3-15 regels; alle details erin |
| **`docs/ARCHITECTURE.md`** | Per architectuur-laag uitleggen "hoe werkt dit en waarom" | Wie de code begrijpt en wil weten waarom keuzes zo zijn | Per concept een sectie met code-pointers |
| **`CLAUDE.md`** | Vaste regels & patronen voor het werken aan deze codebase | AI-assistant + nieuwe collaborators | Stabiel; alleen update als regel verandert |

### Update-protocol bij nieuwe functionaliteit

Elke PR die functionaliteit toevoegt **moet** alle relevante files updaten — niet alleen één van de vier:

- **`README.md`** — alleen aanraken als de feature in de "kernfeatures"-bullet-list verschijnt of de "Recent afgesloten"-regel update vraagt. Anders: niet aanraken (voorkomt versuffing van het overzicht).
- **`docs/ROADMAP.md`** — Epic-status van ⏳ → 🔄 → ✅, sub-stories afvinken, "Effort gerealiseerd" + "Status"-regel updaten. Bij start van een nieuwe Epic: nieuwe sectie aanmaken met aanleiding + sub-stories.
- **`docs/ARCHITECTURE.md`** — als de feature een nieuwe architectuur-keuze introduceert (nieuwe service-laag, sync-pijplijn, security-pattern) of bestaande sectie aanpast. Pure refactors zonder architectuur-wijziging hoeven hier niets.
- **`CLAUDE.md`** — alleen als de feature een nieuw permanent patroon vastlegt (testbeleid, datum-handling, logger-discipline). Eenmalige Epic-werkzaamheden niet hier — die horen in ROADMAP.

### Statussen in ROADMAP

- ✅ afgerond, gemerged op `main`
- 🔄 actief, branch open of in review
- ⏳ gepland of speculatief, nog geen toezegging

Altijd het eerstvolgende logische doel toevoegen zodat de roadmap vooruitkijkt.

### Pure docs-only PR's

Mogen direct op `main` (uitzondering op §8). Voor feature-PR's: code + docs in dezelfde commit. Splits niet kunstmatig in code-PR + docs-PR.

---

## 8. Git Workflow

- Elke code-wijziging gaat via een branch + PR — **nooit direct op `main`**, ook niet voor kleine fixes. Uitzondering: pure README/backlog-updates (docs-only).
- Branchnaam-conventies per type wijziging:
  - `feature/epic-{nr}-{korte-beschrijving}` — nieuwe epics/sprints (bijv. `feature/epic-13-proactive-coaching-engine`)
  - `fix/{korte-beschrijving}` — reguliere bugfixes (bijv. `fix/vibe-score-nil-crash`)
  - `hotfix/{korte-beschrijving}` — productie-kritiek, fast-track merge
  - `security/{alert-id-of-beschrijving}` — security-fixes (bijv. `security/codeql-dob-logging`)
  - `ci/{korte-beschrijving}` — workflow/pipeline-wijzigingen
  - `chore/{korte-beschrijving}` — tech-debt, cleanup, refactors zonder gedragsverandering (bijv. `chore/swiftlint-cleanup`)
  - `docs/{korte-beschrijving}` — pure documentatie-updates (zelden nodig — meestal hoort docs bij een feature-PR; zie §7)
- Workflow per branch:
  1. Branch aanmaken → code bouwen → pushen
  2. Direct na de eerste push **maakt de assistent automatisch de PR aan** via `gh pr create` (titel uit de branch-naam, body met `## Summary` + `## Test plan`-checklist conform de Claude Code-default). Geen aparte goedkeuring vragen — de PR is een doorgeefluik, geen merge-actie.
  3. Gebruiker pulled en test (bij feature branches op device)
  4. Feedback → fixes aanbrengen op **dezelfde** branch (push update bestaande PR automatisch)
  5. Tevreden → gebruiker doet **squash & merge** naar main (de assistent merget niet)
  6. Bij start van de volgende sprint: verwijder gemergte branches lokaal én remote
- PR-discipline:
  - **Eén fix per PR** — geen meeliftende refactors of "en-terwijl-ik-toch-bezig-was" wijzigingen
  - Link altijd de bron in de PR-beschrijving: CodeQL-alert-ID, issue-nummer, crash-report, of user-melding
  - Regression-test toevoegen waar haalbaar (conform §6)
- Security-fixes specifiek:
  - Publieke CodeQL-alerts → reguliere `security/`-branch + PR flow is voldoende
  - Echte exploitable kwetsbaarheden in productie → gebruik **private GitHub Security Advisory** + private fork, publiceer pas ná de fix

---

## 9. Xcode Project Beheer (`project.pbxproj`)

- De `skip-worktree` flag staat standaard aan voor `AIFitnessCoach.xcodeproj/project.pbxproj`. Git negeert daardoor wijzigingen aan dit bestand.
- Bij het aanmaken van een **nieuw Swift-bestand** buiten Xcode (via code-editor of AI-tooling) moet het bestand ook worden toegevoegd aan de Xcode build target in `project.pbxproj`. Dit gaat als volgt:
  1. Voeg `PBXFileReference`, `PBXBuildFile` en de verwijzing in de `PBXGroup` + `PBXSourcesBuildPhase` toe aan `project.pbxproj`
  2. Zet de skip-worktree flag tijdelijk uit: `git update-index --no-skip-worktree AIFitnessCoach.xcodeproj/project.pbxproj`
  3. Stage en commit het bestand
  4. Zet de flag terug: `git update-index --skip-worktree AIFitnessCoach.xcodeproj/project.pbxproj`
- Vergeet dit stap nooit — een bestand dat niet in het project staat zal de CI-build laten falen met `cannot find 'X' in scope`.

---

## 10. Communicatie

- Antwoord en comments **in het Nederlands**, tenzij de gebruiker expliciet Engels vraagt.
- Code-variabelen en functienamen in het Engels (Swift-conventie).
- Wees beknopt — geen onnodige samenvattingen aan het einde van een antwoord.

---

## 11. Logger & Privacy-discipline

- Gebruik **nooit** `print()` in `Services/`, `Models/` of `ViewModels/`. Vervang door `AppLoggers.<categorie>.<level>(...)` (zie `Services/AppLoggers.swift` voor de bestaande categorieën — voeg nieuwe toe als de service buiten de scope van een bestaande valt).
- Privacy-modifiers zijn **verplicht** voor alles dat user-data kan bevatten. Zonder modifier defaultet `Logger` op `.private`, maar maak het expliciet zodat code-review duidelijk is:
  - `privacy: .private` voor HRV, slaapminuten, TRIMP, leeftijd, doeltitels, workout-UUIDs, tokens, RPE/mood, bodyArea-rawValues
  - `privacy: .public` alleen voor framework-foutcodes (bijv. `error.localizedDescription` van iOS-frameworks), tellers (`count, weeks`), en niet-identificerende status-flags (auth-status enums, sport-rawValues)
- In `Views/` is `print()` toegestaan als debug-aid, maar verwijder ze vóór commit. CI-builds hebben geen lint-regel hiervoor — eigen verantwoordelijkheid.
- Géén losse `static let logger = Logger(...)` per service. Centraliseer in `AppLoggers` — voorheen leefden er drie duplicates die uit de hand liepen.

---

## 12. Defensieve App-Init

- Code op het kritieke launch-pad (`ModelContainer`-init, Keychain-migraties, `BGTaskScheduler.register`, fileSystem-bootstraps) gebruikt **nooit** `fatalError` als eerste catch.
- Patroon:
  1. Eerste poging: doe het normaal.
  2. Bij falen: log via `AppLoggers.<x>.error` met `privacy: .public` op de framework-fout, en doe een **fallback** (verwijder corrupte state, gebruik defaults, bouw een lege store).
  3. Pas bij de tweede falen: `fatalError`. Op dat punt is er iets fundamenteel mis (Application Support kapot, schema corrupt) en bricken is correct gedrag.
- Voorbeeld: zie `AIFitnessCoachApp.makeModelContainer()`. Bij migratie-falen verwijdert de fallback de corrupte SQLite-store + WAL/SHM-sidecars en bouwt een lege V<latest>-container, met een UserDefaults-flag (`vibecoach_migrationFallbackAt`) als haakje voor toekomstige UI-melding.
- HK + Strava-data is altijd re-syncbaar via `TriggerAutoSync` zodra de app weer opent; alleen `Symptom` en `UserPreference` zijn lokaal-only. Neem dat data-loss-risico voor lief boven een gebrickte app — een lege DB is hersteld in seconden, een crash-loop is niet hersteld zonder reinstall.
