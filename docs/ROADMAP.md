# VibeCoach Roadmap

**Levende planning:** open & actief werk. Afgeronde epics (volledige historie) → **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**. Deze file blijft bewust kort zodat hij goedkoop als context te laden is (voor mens én AI-agent); detail van afgerond werk leeft in het archief.

Legenda: ✅ afgerond · 🔄 actief · ⏳ backlog

---

## Open werk (in één oogopslag)

| Epic | Wat het is | Pickup-trigger |
|---|---|---|
| ⏳ **#62** | Resterende user-feedback hardening: formulier-validatie, permissie-zichtbaarheid, sync-randpaden, strict concurrency | een concrete unhappy-flow, of vóór een Swift 6-upgrade |
| ⏳ **CI-backlog (#46)** | TestFlight-deploy, snapshot-tests, dependency-scan, perf-checks, concurrency-matrix, release-please | per item een eigen trigger (1e release, UI-regressie…) |
| ⏳ **#59** | Strava Developer Program-compliance: base-URL-wijziging (juni 2027), AI-data-terms checken | naderende Strava-deadlines |
| ⏳ **idee** | Mentale benefit van workouts (nog niet uitgewerkt) | meer "waarom train ik dit"-context gewenst |

---

## Actief & gepland

### ⏳ Epic #62: Resterende user-feedback hardening — formulieren, permissies & concurrency

Consolidatie van de open stories die bleven hangen in twee verder-afgeronde epics: de niet-geleverde hardening-groepen uit **Epic #51** (foutmeldingen, validatie & zichtbaarheid) en de optionele build-setting-promotie uit **Epic #39** (Swift 6 strict concurrency). Allemaal nog relevant — het zijn unhappy-flow-gaten die met het Management-by-Exception-principe schuren — maar geen ervan blokkeert; daarom losgemaakt van hun oorspronkelijke epic en hier gebundeld als één vooruitkijkend doel. Volledige scope + acceptatiecriteria van de #51-stories staan in [issue #265](https://github.com/markclausing/vibecoach/issues/265).

**Stories** (elk een eigen PR):

* **⏳ 62.1 — Doelen aanmaken & beheren (was 51.B):** doel-datum minstens +7 dagen vooruit afdwingen, realistische stretch-tijden per sport, titel-trim bij opslaan, en soft-delete zodat een verwijderd doel geen stale coach-context achterlaat.
* **⏳ 62.2 — AI-provider & API-sleutel (was 51.D):** auto-trim van whitespace bij plakken, prefix-detectie die waarschuwt bij een sleutel van de verkeerde provider (bv. `sk-` onder Gemini), en test-sleutel-feedback die persistent blijft na een providerwissel of app-herstart.
* **⏳ 62.3 — Onboarding & toestemmingen (was 51.E):** HealthKit als vereiste stap (niet stil overslaanbaar), notificaties expliciet optioneel, status-banner wanneer een permissie is overgeslagen, detectie van achteraf-ingetrokken toegang, en een permissie-status-overzicht in Settings.
* **⏳ 62.4 — Data syncen — resterende paden (was 51.F3/F4/F6):** HealthKit per-type permissie-afhandeling, weer-fout non-blocking maken met een retry-marker i.p.v. een harde onderbreking, en captive-portal-detectie (online maar achter een login-portal).
* **⏳ 62.5 — Proactieve coach (achtergrond) (was 51.G):** status-rij in Settings die toont of Engine A/B draait, een notificatie-permissie-pre-check vóór registratie, en zichtbaarheid van een registratie-fout i.p.v. een stille mislukking.
* **⏳ 62.6 — Strict Concurrency Checking → `Complete` (was 39.3):** de project-build-setting promoten zodat nieuwe Sendable-/actor-isolation-regressies harde compile-errors worden i.p.v. warnings. Mogelijk komen er nieuwe warnings boven die eerst opgelost moeten worden; daarom een aparte PR zodra de codebase een tijd stabiel is. Bouwt door op CI-backlog-story 46.B5 (concurrency-strict-build als matrix-cel).

**Pickup-trigger:** een concrete unhappy-flow die een gebruiker raakt (een doel met een datum in het verleden, een verkeerd geplakte sleutel, of verwarring over welke permissies actief zijn), of de wens om vóór een Swift 6-upgrade de concurrency-discipline af te dwingen.

**Volgorde-suggestie:** begin met 62.1 + 62.2 (formulier-validatie, kleinste oppervlak, directe gebruikerswinst), dan 62.3 + 62.5 (permissie-zichtbaarheid), dan 62.4 (sync-randpaden), en 62.6 als losse concurrency-PR wanneer het uitkomt.

---

### ⏳ CI-backlog (uit Epic #46): pipeline-uitbreidingen

Zes bewust-uitgestelde CI-uitbreidingen uit het afgeronde **Epic #46** — geen toezegging, elk met een eigen pickup-trigger. Volledige rationale per item staat in het [archief (Epic #46)](ROADMAP-archive.md).

* **⏳ 46.B1 — TestFlight-deploy** op merge naar main (vereist Apple Developer-account + App Store Connect API-key + signing-certs in GitHub Secrets). Trigger: TestFlight-flow automatiseren i.p.v. handmatig archive uploaden.
* **⏳ 46.B2 — Snapshot-tests** (`swift-snapshot-testing`, PNG-diff op Dashboard/Goals/Chat/Settings). Trigger: een UI-regressie die de XCUITests misten.
* **⏳ 46.B3 — Dependency vulnerability scan** (`dependency-review-action` op `Package.*`). Trigger: actief SPM-gebruik voor third-party deps.
* **⏳ 46.B4 — Performance regression checks** (build-tijd-tracking + lichte `XCTMetric`-baseline). Trigger: gemelde traagheid + behoefte aan objectieve baselines.
* **⏳ 46.B5 — Concurrency-strict-build als matrix-cel** (`SWIFT_STRICT_CONCURRENCY=complete`). Trigger: zodra Epic #62 story 62.6 gedaan is — bouwt daarop voort.
* **⏳ 46.B6 — Semver via `release-please`** + git-tag-gebaseerde `MARKETING_VERSION`. Trigger: eerste echte release (TestFlight/App Store).

---

### ⏳ Epic #59: Strava Developer Program-wijzigingen — compliance & continuïteit

Idee voor een toekomstige Epic — nog niet uitgewerkt. Strava heeft [wijzigingen aan het Developer Program aangekondigd](https://communityhub.strava.com/insider-journal-9/an-update-to-our-developer-program-13428) met meerdere gefaseerde deadlines. VibeCoach leest de eigen activiteiten van de gebruiker (HR/vermogen/GPS/streams) via de Strava API en voedt die in de AI-coach — dus we moeten de impact in kaart brengen en op tijd handelen.

**Huidige stand in de code (grounding):** de token gaat al via de `Authorization: Bearer`-header (`FitnessDataService` regels 119/153/191/229/279/334) → **al compliant** met de 2027-header-eis. Activity-data wordt **direct** van `https://www.strava.com/api/v3/...` opgehaald (`FitnessDataService`); alleen de OAuth-token-refresh loopt via de eigen Cloudflare Worker (`Secrets.stravaProxyBaseURL`, `/oauth/strava/refresh`, houdt de `client_secret`). **Geen** club-endpoints in gebruik.

**Deadlines & impact:**

1. **30 juni 2026 — abonnementsplicht (✅ AFGEDEKT).** Standard Tier-developers hebben vanaf deze datum een betaald Strava-*abonnement* (premium membership) nodig om de API te blijven gebruiken — niet enkel een gratis account. **Status: de maintainer heeft een betaald Strava-abonnement, dus aan deze eis is voldaan; geen actie nodig.** Persoonlijk gebruik = 1 atleet valt bovendien ruim binnen de Standard Tier-limiet van 10 atleten self-service. (Mocht het abonnement ooit vervallen, dan valt de Strava-sync weg en draait de app HealthKit-only door — zie Open punten.)
2. **Intermediary-platform-ban.** "Apps routing Strava data through third-party intermediary platforms are no longer supported." → Verifiëren of de eigen Cloudflare Worker hieronder valt. Hij doet alleen OAuth-token-exchange/-refresh (first-party, eigen `client_secret`); de **activity-data gaat direct** van Strava naar de app, niet via de Worker. Waarschijnlijk geen "third-party intermediary data platform", maar bevestigen tegen de nieuwe terms; zo nodig de token-exchange anders inrichten.
3. **1 september 2026 — endpoint-deprecaties.** Club Activities/Administrators/Members verdwijnen; Segments Explore alleen nog voor Extended Tier. → **Geen impact verwacht** (app gebruikt deze endpoints niet) — kort bevestigen.
4. **1 juni 2027 — technische wijzigingen.** Base-URL verandert van `https://www.strava.com/api/v3` naar `https://www.api-v3.strava.com`; tokens verplicht in request-headers. → Code: de ~6 hardgecodeerde URLs in `FitnessDataService` + `StravaAuthService` omzetten (centraliseren in één base-URL-constante is meteen een nette refactor); de header-auth is al in orde. Klein werk, ruim op tijd te plannen.
5. **AI-scraping / data naar externe LLM.** Strava benadrukt zorgen over AI-scraping; de aankondiging legt geen expliciete API-term-restrictie op AI/ML-gebruik op, maar onze coach stuurt activiteitsdata naar een externe LLM (BYOK). → De Strava API-terms checken of het doorsturen van de **eigen** data van de gebruiker naar een AI-provider is toegestaan, en dat documenteren (privacy/§11).

**Open punten / pickup-trigger:** punt 1 is **tijdkritisch** (deadline 30 juni 2026, maintainer-actie nu). Code-werk (punt 4) kan later in een aparte story. Overweeg ook (a) Strava's nieuwe **MCP-tool voor persoonlijke data-analyse** als alternatief/aanvullend pad, en (b) graceful degradation: bevestigen dat de app HealthKit-only blijft werken als Strava-toegang wegvalt (sluit aan op §12 defensive init). **Pickup-trigger:** de naderende 30-juni-deadline, of een Strava-sync-storing door een van de bovenstaande wijzigingen.

---

### ⏳ Epic-backlog: Mentale benefit van workouts

Idee voor een toekomstige Epic — nog niet uitgewerkt. Gedachte: niet alleen fysieke metrics tonen (TRIMP, HR, recovery), maar ook iets over mood/energie/stress-impact zodat de coach kan zeggen "je voelt je hier de rest van de dag goed door" of "deze sessie helpt je stress af te bouwen". Open punten: welke signalen (HRV-respons na rit, post-RPE-mood, slaap-respons in nacht erna), welke UI (extra tegel onder Vibe Score? Veld op WorkoutAnalysisView?), hoe de coach dit framet, en hoe we het onderscheiden van pure fysieke load. Pickup-trigger: gebruiker wil meer expliciete "waarom train ik dit"-context bij workouts.

---

## Recent afgerond (laatste 5)

- ✅ **#61** Security hardening — privacy & opslag-discipline (review-opvolging)
- ✅ **#60** Mijlpaal-inzicht per fase in de Doelen-view (uitklapbaar)
- ✅ **#58** README als showcase — gebruiker-gerichte productpagina
- ✅ **#37** Internationalisatie & Engelstalige codebasis (NL/EN/DE/ES)
- ✅ **#57** RPE-check-in vereenvoudigen — één-tik inspanning + gevoel

Volledige historie (Fase 1–9 + alle afgeronde epics) staat in **[docs/ROADMAP-archive.md](ROADMAP-archive.md)**.
