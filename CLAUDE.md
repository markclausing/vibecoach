# VibeCoach — Architectuur & Ontwikkelregels voor Claude

Dit bestand bevat de vaste project-instructies voor de AI-assistent (Claude).
Lees dit bij elke sessie als basis voor alle beslissingen.

---

## 0. Meta: Autonoom Context Management

**Proactieve Updates:** Claude is verantwoordelijk voor het actueel houden van dit bestand. Bij een nieuwe architectuurkeuze, een structureel opgeloste bug (bijv. een iOS-quirk), of een nieuwe project-standaard: update `CLAUDE.md` direct en zonder toestemming te vragen.

**Token Optimalisatie (The Cache):** Als er veel heen-en-weer wordt gepraat over een complex concept, vat Claude de eindconclusie samen, voegt deze toe als harde regel, en meldt: *"Ik heb de regels bijgewerkt. Je kunt nu `/compact` typen om tokens te besparen."*

**Epic Overgangen:** Bij de start van een nieuwe Epic controleert Claude zowel `CLAUDE.md` als `README.md` op oude of irrelevante regels die verwijderd kunnen worden om de cache schoon te houden.

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

Vereist bij elke `@Model`-wijziging die niet pure additions is — rename, type-change, of een nieuwe `@Attribute(.unique)` / `#Unique` op een bestaand veld:

1. **Snapshot het oude schema** in `Models/SchemaV<N>.swift` als `enum SchemaV<N>: VersionedSchema`. Nested `@Model` types houden **dezelfde unqualified naam** als de live types (bijv. `SchemaV1.Symptom` — niet `V1Symptom`) zodat de SwiftData entity-naam matcht met wat in de bestaande store staat. Mismatchende entity-namen breken de migratie met "Cannot use staged migration with an unknown model version".
2. Voeg een nieuwe `MigrationStage` toe aan `AppMigrationPlan`. Schemas die ongewijzigd blijven (bijv. `FitnessGoal`) worden in beide schema's direct gerefereerd — niet ge-snapshot.
3. **Type-changes** (bijv. `String` → enum): capture-in-`willMigrate` + restore-in-`didMigrate`. `@Attribute(originalName:)` alleen kan een rename mét behoud van type aan, géén impliciete type-conversie naar een RawRepresentable-enum.
4. **Nieuwe unique-constraints op vol veld**: dedupe in `willMigrate` vóór de schema-flip — anders faalt de constraint-applicatie hard met een SQLite-violation.
5. Schrijf altijd een `SchemaMigrationV<N>To<M>Tests` met een **file-backed** seed-store als happy-path-vangnet. In-memory stores werken niet voor migratie-paden (er is geen V<N>-store-bestand om vanaf te starten).

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

## 6. Testen

- Elke nieuwe functionaliteit krijgt **Unit Tests (XCTest)** voor de onderliggende logica.
- Voor kern-flows ('Happy Paths') ook **XCUITest UI-tests**.
- Geen zware test-suite: alleen wat écht waarde heeft. Geen tests schrijven voor triviale getters of SwiftData-boilerplate.

---

## 7. README Protocol

- Elke PR **moet** een README-update bevatten in dezelfde commit.
- Afgeronde sprints afvinken (✅), actieve sprints markeren (🔄), geplande sprints markeren (⏳).
- Altijd het eerstvolgende logische doel toevoegen zodat de roadmap vooruitkijkt.
- Epic-statussen en roadmap worden **uitsluitend** bijgehouden in `README.md`.

---

## 8. Git Workflow

- Elke code-wijziging gaat via een branch + PR — **nooit direct op `main`**, ook niet voor kleine fixes. Uitzondering: pure README/backlog-updates (docs-only).
- Branchnaam-conventies per type wijziging:
  - `feature/epic-{nr}-{korte-beschrijving}` — nieuwe epics/sprints (bijv. `feature/epic-13-proactive-coaching-engine`)
  - `fix/{korte-beschrijving}` — reguliere bugfixes (bijv. `fix/vibe-score-nil-crash`)
  - `hotfix/{korte-beschrijving}` — productie-kritiek, fast-track merge
  - `security/{alert-id-of-beschrijving}` — security-fixes (bijv. `security/codeql-dob-logging`)
  - `ci/{korte-beschrijving}` — workflow/pipeline-wijzigingen
- Workflow per branch:
  1. Branch aanmaken → code bouwen → pushen
  2. Gebruiker pulled en test (bij feature branches op device)
  3. Feedback → fixes aanbrengen op **dezelfde** branch
  4. Tevreden → gebruiker maakt PR → CI draait → **squash & merge** naar main
  5. Bij start van de volgende sprint: verwijder gemergte branches lokaal én remote
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
