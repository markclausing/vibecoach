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

- Elke epic of sprint werkt op een **feature branch** — nooit direct op `main`.
- Branchnaam conventie: `feature/epic-{nr}-{korte-beschrijving}` (bijv. `feature/epic-13-proactive-coaching-engine`).
- Workflow per sprint:
  1. Feature branch aanmaken → code bouwen → pushen
  2. Gebruiker pull de branch in Xcode en test op device
  3. Feedback → fixes aanbrengen op **dezelfde** feature branch
  4. Tevreden → gebruiker maakt PR → CI draait → merge naar main
  5. Bij **start van de volgende sprint**: verwijder de vorige (gemergte) branch lokaal én remote

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

## 10. GitHub Project Workflow

Claude Code must manage GitHub Issues and the Project Board actively during development.

### Issue Lifecycle

- **Sprint start:** Move all issues for the current sprint to the "Sprint Backlog" column on the GitHub Project board.
- **Starting work:** When beginning work on any issue (planned, bug, or otherwise), move it to "In Progress" on the Project board.
- **Ready for review:** When work on an issue is complete:
  - Move the issue to "Review" on the Project board.
  - Assign the issue to the project owner.
  - Add a comment on the issue explaining how to test it: what to look at, what URLs to visit, what to click, what the expected result is.
  - Do NOT close the issue — the owner closes it after review.
- **Bugs:** Follow the same lifecycle, even for quick fixes. Create an issue, move it through In Progress → Review.

### Sprint Closure

Before declaring a sprint complete, verify:

- [ ] All sprint issues are in "Done" or "Review" status.
- [ ] No sprint issues are still in "In Progress" or "Sprint Backlog".
- [ ] If any issues are in "Review", notify the owner and wait for them to be moved to "Done" before closing the sprint.

### Commit References

- Always reference the issue number in commit messages: `feat(auth): implement sign-up flow (#3)`
- Use `closes #N` in PR descriptions to auto-close issues on merge, but only after review is complete.

---

## 11. Communicatie

- Antwoord en comments **in het Nederlands**, tenzij de gebruiker expliciet Engels vraagt.
- Code-variabelen en functienamen in het Engels (Swift-conventie).
- Wees beknopt — geen onnodige samenvattingen aan het einde van een antwoord.
