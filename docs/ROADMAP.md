# VibeCoach Roadmap

Complete epic-historie en backlog. De root-`README.md` blijft beknopt; deze file is het archief én de vooruitkijkende planning.

Legenda: ✅ afgerond · 🔄 actief · ⏳ backlog

---

## Afgeronde Epics

### ✅ Fase 1–9: Fundering & Intelligente Coach

| Fase | Wat er gebouwd is |
|------|-------------------|
| **1–5** | iOS App (SwiftUI) & SwiftData, OAuth2 Strava, Node.js webhook-backend met APNs (later vervangen door Engine A — zie Epic 13), deep-linking op `activityId` |
| **6** | Historische sync, context-injectie & proactieve overtraining-waarschuwingen |
| **7** | Apple HealthKit integratie — Banister TRIMP berekening (HRR, Cardiac Drift, Training Load) lokaal op device |
| **8** | Interactieve 7-daagse trainingskalender; Readiness Calculator injecteert cumulatieve TRIMP + actieve doelen in de prompt |
| **9** | Smart Expiring Memory (tijdelijke blessures krijgen een vervaldatum), workout-acties (Overslaan / Alternatief), Performance Baseline (gemiddeld tempo geïnjecteerd in AI-prompts) |
| **10** | Open Source release — secrets verwijderd, documentatie op orde |
| **11** | Coach UX refactor: `TrainingPlanManager` als Single Source of Truth, centrale TabBar Coach-knop |
| **12** | Multi-Goal Burndown Chart (Swift Charts, schuifbaar), TRIMP Explainer-kaart, hybride Forecast-lijn (gepland schema + historische burn rate) |

---

### ✅ Epic 13: Proactieve Coach & Background Sync

**Dual Engine Architecture** die de app wakker maakt zonder dat de gebruiker iets hoeft te doen. Zie [ARCHITECTURE.md](ARCHITECTURE.md) voor de technische uitleg.

* **Engine A (Action Trigger):** `HKObserverQuery` + `enableBackgroundDelivery`.
* **Engine B (Inaction Trigger):** `BGAppRefreshTask` via `BGTaskScheduler`.
* **Recovery Mode:** `requestRecoveryPlan()` bouwt automatisch een gedetailleerde prompt en instrueert de AI een 7-daags bijgestuurd schema te produceren.
* **Fysiologische Guardrails:** Harde limieten in de AI-prompt — 10–15% progressieregel, Base Building bij >8 weken resterend, max 60 minuten voor binnensessies.

---

### ✅ Epic 14: De Vibe Score — Readiness

**HealthKit meets AI:** dagelijkse lichaamsbatterij (0–100) die de coach stuurt.

* `heartRateVariabilitySDNN` (HRV) en `sleepAnalysis` via HealthKit — volledig lokaal, privacy-first.
* `ReadinessCalculator` combineert Slaap (50%, lineair 5–8u) + HRV (50%, actueel vs. 7-daagse persoonlijke baseline) tot een score van 0–100.
* `VibeScoreCardView` (groen ≥80, oranje 50–79, rood <50) bovenaan het dashboard.
* De Vibe Score wordt gecached in `AppStorage` en geïnjecteerd in *iedere* AI-prompt. Harde systeeminstructie: de AI mag de score nooit weerspreken.

---

### ✅ Epic 16: Dynamische Periodisering & Macrocycli

De app denkt in trainingsfasen — niet langer een lineaire burndown.

* `TrainingPhase` enum (`.baseBuilding`, `.buildPhase`, `.peakPhase`, `.tapering`), automatisch bepaald op basis van weken resterend.
* Wekelijkse TRIMP-target schaalt mee — ×1.00 (Base), ×1.15 (Build), ×1.30 (Peak), ×0.60 (Taper). Tapering-overload detectie triggert aparte rode waarschuwing.
* De coach ontvangt per doel een `[PERIODISERING]` blok met fase-specifieke restricties én de concrete wiskundig aangepaste TRIMP-target.

---

### ✅ Epic 17: Goal-Specific Blueprints

Hardcoded sportwetenschappelijke regels per discipline.

* `GoalBlueprint` struct met `minLongRunDistance`, `taperPeriodWeeks`, `weeklyTrimpTarget`, `essentialWorkouts`. Hardcoded Marathon (28+32 km), Halve Marathon (16+18 km), Fietstocht (60+100 km).
* `BlueprintChecker` detecteert blueprint-type via sleutelwoorden of SportCategory-fallback.
* Blueprint-milestones + periodization-context geïnjecteerd in alle AI-prompts.
* `PhaseBadgeView` boven het schema, `MilestoneProgressCard` met voortgangsbalken per doel.

---

### ✅ Epic 18: Subjectieve Feedback — RPE & Mood

Hoe zwaar voelde de training? — onafhankelijk van wat de hartslagmeter zegt.

* **Post-Workout Check-in:** `PostWorkoutCheckinCard` verschijnt op het dashboard na een echte training (≤48u, ≥15 min, TRIMP ≥15). RPE-slider (1–10) + vijf stemming-knoppen.
* Woon-werk ritten en korte wandelingetjes worden automatisch overgeslagen.
* De AI ontvangt een `[SUBJECTIEVE FEEDBACK]` blok in iedere prompt. Laag TRIMP + RPE ≥8 = vroeg waarschuwingssignaal voor overtraining.

---

### ✅ Epic 19: Tech Debt, MVVM Refactor & UI Testing

Uitgebreide opschoning. Code coverage gestegen naar 62%.

* **Magic Numbers → Constanten:** `WorkoutCheckinConfig` enum centraliseert RPE-drempelwaarden.
* **Accessibility Identifiers:** Kerncomponenten gemarkeerd voor robuuste UI-testbaarheid.
* **UI-testsuite:** 8 XCUITests voor TabBar, Dashboard, navigatie en RPE check-in. HealthKit- en notificatie-popups gebypassed via `-isRunningUITests`.
* **Unit Tests:** `ReadinessCalculatorTests` (8 tests) + `TrainingPhaseTests` (11 tests).

---

### ✅ Epic 20: App Store Ready — Onboarding & Polish

* **Sprint 20.1 — BYOK & Multi-Provider:** `AIProvider` enum (Gemini / OpenAI / Anthropic). `AIProviderSettingsView` in Instellingen. `NoAPIKeyView` lege staat in de Coach-tab als er geen sleutel is.
* **Sprint 20.2 — Onboarding Flow:** 4-pagina `TabView` carousel met inline BYOK-invoerkaart. Permissies uitsluitend via knoppen, nooit automatisch.
* **Sprint 20.3 — Splash Screen & App Icon:** Native splash via `UILaunchScreen` in `Info.plist`. Onboarding beveiligd: geen enkele permissie-request buiten expliciete knoppen.

---

### ✅ Epic 14b: Blessure-Impact Intelligentie & Vibe Score Stabiliteit

* **14b.1 — Injury-Impact Matrix:** Penalty-multiplier (1.0–1.4×) verhoogt de effectieve TRIMP bij risicovolle sportkoppeling.
* **14b.2 — ACWR-Bannerlogica:** Dashboard-banner gebaseerd op Acute:Chronic Workload Ratio (drempel 1.5×). States: `overreached`, `lowVibeHighLoad`, `behindOnPlan`.
* **14b.3 — Chat UX & Retry:** Verbeterde prompt-suggesties, `Retry`-knop bij AI-fouten.
* **14b.4 — Vibe Score Auto-Berekening:** `DashboardView` berekent de Vibe Score automatisch bij `onAppear`. 5s time-out via `withTaskGroup`. HRV-venster vergroot naar 48u.

---

### ✅ Epic 21: Externe Factoren — Weer & Slaap

* **21.1 — Open-Meteo Weersverwachting:** `WeatherManager` haalt de 7-daagse weersverwachting op. Coach wisselt trainingen bij ⚠️ SLECHT BUITENWEER. Wind >30 km/u triggert fietssuggestie naar windstillere dag. `WeatherBadgeView` op elke `WorkoutCardView`.
* **21.2 — Slaapfasen (Sleep Stages):** `fetchSleepStages()` haalt `.asleepDeep`, `.asleepREM`, `.asleepCore` op. Strafpunten bij <15% diepe slaap. `SleepStagesBarView` in de Vibe Score kaart.

---

### ✅ Epic 23: Blueprint Analysis & Future Projections

* **23.1 — Target Gap Analysis:** `ProgressService` berekent het gap tussen het lineaire verwachte en het werkelijk behaalde volume. `GapAnalysisCardView` toont voortgangsbalk per TRIMP en km.
* **23.2 — Future Projection Engine:** `FutureProjectionService` extrapoleert een 3-weeks sliding window trendlijn. `ProjectionStatus`: `alreadyPeaking / onTrack / atRisk / unreachable`.
* **23.3 — Visual Progress Hub:** `BlueprintTimelineView` met Ideaal / Actueel / Prognose lijnen. `GoalDetailContainer` bundelt alles per doel.

---

### ✅ Epic 24: Nutrition & Fueling Engine

* **24.1 — Fysiologisch Profiel:** `UserProfileService` haalt gewicht, lengte, leeftijd en geslacht op via HealthKit met fallbacks. `NutritionService` berekent BMR (Mifflin-St Jeor) en koolhydraten/vocht-behoefte per zone.
* **24.2 — Two-Way Sync:** `PhysicalProfileSection` in Instellingen — leeftijd/geslacht read-only, gewicht/lengte bewerkbaar. Bronbadge per waarde (❤️ HealthKit / 📱 Lokaal / ⚠️ Standaard).
* **24.3 — Voedings UI:** `WorkoutStatsRow` fueling-chips (⏱/⚡/💧/🍌). `WorkoutFuelingSectionView` met per-15-min timing-advies.

---

### ✅ Epic 26: UI Test Suite Fixes & ProgressService Unit Tests

* 8 UI-tests draaien stabiel in CI na race-conditie-fixes.
* `ProgressServiceTests` volledige happy-path dekking.
* Coverage: 54% → **62%**.

---

### ✅ Epic 27: Test Coverage Verbeteren

* `FutureProjectionService` tests (trendlijn-algoritme, veiligheidslimiet, `ProjectionStatus`-varianten).
* `UserProfileService` tests (HealthKit-fallback-keten, Mifflin-St Jeor BMR).
* Coverage eindresultaat: **63%** (target ≥75% niet gehaald).

---

### ✅ Epic #28: Doel-Intentie, Meerdaagse Evenementen & Stretch Goals

* `EventFormat` (`.singleDayRace`, `.multiDayStage`), `PrimaryIntent` (`.completion` / `.peakPerformance`), optionele `StretchGoal`.
* `PeriodizationEngine` plant back-to-back duurtrainingen bij meerdaagse tochten.
* AI-prompt prioriteert altijd de finishlijn boven de doeltijd zodra de atleet vermoeid is.

---

### ✅ Epic #29: Visual Overhaul — 'Serene' Thema

* **29.1 — Theme Engine:** `ThemeManager` + `Theme` enum (Moss, Stone, Mist, Clay, Sakura, Ink). Persistent via `UserDefaults`.
* **29.2 — Design System:** Adaptive `UIColor { traits in }` closures. `SereneIconStyle` voor hiërarchische SF Symbols.
* **29.3 — Instellingen & UI Injectie:** `ThemePicker` met live preview. Dynamische tab-iconen via `ThemeManager.icon(for:)`.
* **29.4 — Global Theme Injection:** Alle hardcoded `Color.blue` en `Color.accentColor` vervangen door `themeManager.primaryAccentColor`.

---

### ✅ Epic #30: V2.0 Card-Based UX Overhaul

* **30.1 — Dashboard V2:** Floating card lay-out. `DashboardHeaderView`, `VibeScoreCardV2`, `WeekTimelineView`, `TrendWidgetView`, `DashboardBannerView`. Build number via CI (`agvtool`).
* **30.2 — Interactive Coach Chat:** `CoachV2HeaderView`, `CoachTextCard`, `CoachInsightCard`, `PlanAdjustmentCard`. Tab-iconen naar outlined stijl.
* **30.3 — Goals V2:** `List` → card-gebaseerde `ScrollView`. Voortgangsbalken per trainingsfase per doelkaart.
* **Bugfixes (PR #169):** `ColorColor` typo, `TimeInterval`-wiskunde → `Calendar.dateComponents`, `recoveryReason` op `AthleticProfile`, UI-testsuite volledig bijgewerkt voor V2.0.

---

### ✅ Epic #31: V2.0 Onboarding Experience

Vijf-schermen flow in Serene/Mos-stijl. Elk scherm toont een 'live preview' (Vibe Score ring, TRIMP-bars, coach-notificatie) vóórdat permissies worden verleend.

* **31.1 — State & Navigatie:** `@AppStorage("hasCompletedOnboarding")` als poortwachter. `OnboardingTemplateView` als wrapper; `OnboardingView` als `TabView(selection:)`.
* **31.2 — HealthKit & Engine A:** `HealthKitManager.shared.requestOnboardingPermissions()`. Na grant start `ProactiveNotificationService.shared.setupEngineA()`.
* **31.3 — Stijl-fundament:** Kaart-stijl afgestemd op Dashboard (`cornerRadius 16`, zachte `shadow`).
* **31.4 — Persistence:** `UserConfiguration` (SwiftData `@Model`) voor `onboardingDate`. API-sleutels via `KeychainService` — nooit `UserDefaults`.
* **31.6 — Prototype-uitlijning:** 5-staps flow conform prototype. Doel-keuzescherm verwijderd. Continue voortgangsbalk + "X / N" teller. System default color scheme expliciet gerespecteerd.

---

### ✅ Epic #34: V2.0 Fit & Finish — UI Polish & Tech Debt

* **34.1 — Safe Area:** `scrollEdgeMaterial(isActive:)` modifier voor scroll-aware `regularMaterial` strip onder de statusbalk.
* **34.2 — Dynamisch Build- & Versienummer:** Uit `Bundle.main.infoDictionary` in `SettingsView`.
* **34.3 — Smart Insights, Haptics & Empty States:** Dynamische `CoachInsightCard`-observaties. `.impact(.medium)`-feedback via `Haptics`-helper. Lege lijsten → `ContentUnavailableView`.
* **34.4 — UI Consistente Spacing:** `lineLimit` + `minimumScaleFactor` voor iPhone SE.
* **34.5 — Hardcoded Data Cleanup:** KORT/WAT IK ZIE-kaarten volledig data-gedreven via `@Query`. Dummy-toggles verwijderd uit Settings.

---

## Backlog

### ✅ Epic #32: Deep-Dive Fysiologische Analyse

Van gemiddelden naar granulaire fysiologische patronen. De coach leest het volledige verhaal uit de ruwe tijdreeksdata.

* **✅ Story 32.1 — Time-Series Data Pipeline (PR #200, #201):** `WorkoutSample` `@Model` (Route A: `workoutUUID` foreign key naar `HKWorkout`, geen redundant Workout-cache), `SampleResampler` met drie strategieën (average voor HR/Power/Cadence, linear interpolation voor Speed, delta-accumulation voor Distance) en een `@ModelActor`-store die idempotent samples vervangt per workout. HK-fetch via `HKQuantitySeriesSampleQuery` over alle parent-samples. `DeepSyncService` haalt eenmalig alle workouts uit de afgelopen 30 dagen op en jaagt ze door de ingest-pijplijn — idempotentie via `processedWorkoutUUIDs` (UserDefaults JSON-set), `hasCompletedInitialDeepSync`-flag gaat pas op `true` als ALLE workouts in het venster verwerkt zijn. Unit tests in `SampleResamplerTests` + `DeepSyncServiceTests`.
* **✅ Story 32.2 — Annotated Charts UI (PR #202, #204, #205):** `WorkoutAnalysisView` met gestapelde Swift Charts (HR `LineMark` boven, snelheid/vermogen `AreaMark` onder) en een gedeelde scrubber-overlay die beide assen synchroon volgt. Een floating header toont tijd · BPM · m/s of W onder de scrubber-positie. Entry-point: `RecentWorkoutsSection` op het Dashboard onder TrendWidget — alleen HealthKit-records (UUID-parseerbare `id`) zijn klikbaar. Strava-records tonen we als statische context-rij. Lege-staat ("Deep Sync loopt op de achtergrond") als de `WorkoutSample`-set leeg is. Pure-Swift helpers (`WorkoutAnalysisHelpers`) voor nearest-sample-lookup en secondary-series-keuze, met 8 unit tests. **Annotation-pins op de chart bewust gesplitst naar 32.3b** zodra de AI-prompt-format vaststaat.
* **✅ Story 32.3a — Pure-Swift pattern-detectoren:** `WorkoutPatternDetector` (pure-Swift, AppStorage-vrij) met detectoren voor de vier fysiologische fenomenen: **aerobic decoupling** (HR-drift relatief aan vermogen of pace; Pa:HR-drempels 3 / 5 / 8% mild/moderate/significant), **cardiac drift** (HR-only drift tussen helft 1 en helft 2 in aerobic workouts), **cadence fade** (cadence-daling tussen het eerste en laatste kwart, met zero-cadence filter zodat stops geen vals signaal geven), en **HR-recovery** (BPM-drop in 60s na de globale piek-inspanning). Returneren `WorkoutPattern`-value-types met `Severity`, `ClosedRange<Date>` en human-readable detail-string. 22 unit tests in `WorkoutPatternDetectorTests` dekken drempel-grenzen, skip-paden, plateau-edge-cases en `detectAll`-aggregatie.
* **✅ Story 32.3b — Annotation-pins + Coach-analyse-card:** Patronen uit 32.3a renderen als `PointMark`-annotaties op de HR-chart in `WorkoutAnalysisView`, gekleurd op severity (mild/moderate/significant → groen/oranje/rood). Direct boven de chart: een chip-row die per patroon `kind` + numerieke waarde toont, en een "Coach-analyse"-card die via `WorkoutInsightService` (Gemini) een 3-zin synthese van de patronen genereert ("decoupling + cardiac drift = aerobic ceiling overschreden, kan door hitte komen — was dat bewust drempel-werk?"). `WorkoutInsightCache` houdt de narrative per `activityID + pattern-fingerprint` zodat opnieuw openen van dezelfde workout geen API-call kost; bij re-classificatie invalidert de cache automatisch. `WorkoutPatternFormatter` (pure-Swift) serialiseert de patronen naar prompt-snippets en bouwt de fingerprint. 22 unit tests dekken formatter + cache.
* **✅ Story 32.3c — AI-context-injectie in chat-coach:** `ChatViewModel.workoutPatternsContext` (`@AppStorage`) wordt door `DashboardView.refreshWorkoutPatternsContext()` gevuld met significante patronen uit de afgelopen 7 dagen, en `buildContextPrefix` injecteert ze in elke chat-prompt onder een nieuw `[FYSIOLOGISCHE PATRONEN IN RECENTE WORKOUTS:]`-blok met expliciete gedragsregels (alleen reageren als gebruiker reflecteert, drift+decoupling triggeren een gerichte vraag, trage HR-recovery koppelen aan TRIMP/VibeScore voor herstel-advies). Mild patronen worden uitgefilterd zodat de prompt rustig blijft.

---

### ✅ Epic #33: Geavanceerde Sessie-architectuur

Trainingen zijn sessies met expliciete fysiologische intentie. Afgerond april 2026 — gebruiker heeft de hele flow on-device gevalideerd: sessietypes worden auto-geclassificeerd én handmatig overrulebaar, swaps zijn heilig in elke prompt, en de coach kalibreert zijn toon op intent vs. uitvoering.

* **✅ Story 33.1 — Sessie-Type Taxonomie:** Gesplitst in twee PR's vanwege scope.
  - **✅ 33.1a — Domain & classifier:** `SessionType` enum (7 cases: `vo2Max`, `threshold`, `tempo`, `endurance`, `recovery`, `social`, `race`), `SessionIntent` struct met zonebereik + verwachte RPE + coachingSummary per type, `sessionType` als optionele property op `ActivityRecord` (lightweight migration), en `SessionClassifier` met drie strategieën (keywords, zone-distributie via `WorkoutSample`, average-HR-fallback). 20 unit tests in `SessionClassifierTests`.
  - **✅ 33.1b — UI override + auto-classifier + AI-context-injectie:** `HeartRateZones` helper voor maxHR via Tanaka-formule (208 - 0.7×leeftijd) met 190 fallback. `HealthKitSyncService` runt classifier bij elke nieuwe `ActivityRecord` op basis van avg HR + duur (manual override beschermd — classifier overschrijft nooit een handmatig gekozen type). `WorkoutAnalysisView` krijgt een Menu-override (SF Symbols + capsule, Serene-stijl) die direct in SwiftData saven. `LastWorkoutContextFormatter` (testbaar) bouwt het laatste-workout-blok in de prompt en voegt `sessionType.displayName` + `intent.coachingSummary` toe — coach krijgt tekstuele intent ("Actief herstel" i.p.v. enkel "recovery"). 8 unit tests in `LastWorkoutContextFormatterTests` + 7 in `HeartRateZonesTests`.
* **✅ Story 33.2 — Flexibele Planning (The 'Swap'):** Gesplitst in twee PR's vanwege scope.
  - **✅ 33.2a — Verplaats sessie + USER_OVERRIDE in prompt:** `SuggestedWorkout` krijgt optionele `scheduledDate: Date?` en `isSwapped: Bool` met backwards-compatible `Codable`-decode (oude AppStorage plans blijven intact). `displayDate` computed kiest tussen override en `resolvedDate`. `TrainingPlanManager.moveWorkout(_:to:)` schrijft de override + hersorteert op `displayDate` zodat de UI direct meebeweegt. UI: nieuwe "Verplaats sessie"-actie in `WorkoutDetailView` + dag-chips-sheet voor de huidige week. AI-context: nieuwe `UserOverrideContextFormatter` produceert het `[USER_OVERRIDE]`-blok met expliciete instructie aan de coach om verplaatste sessies te respecteren. 5 unit tests voor de formatter.
  - **✅ 33.2b — Reset Schema knop + AI-replan:** "Herschrijf schema"-knop in `WeekTimelineView`, alleen zichtbaar bij ≥1 verplaatste sessie. Hergebruikt bestaande `sendHiddenSystemMessage`-flow met een `pendingPlanUpdateMode`-flag die de JSON-pickup naar `mergeReplannedPlan(_:)` route i.p.v. `updatePlan(_:)`. App-side merge garandeert dat verplaatste sessies leidend zijn — AI-output op heilige dagen wordt genadeloos gefilterd (defense in depth tegen LLM-hallucinaties). `PlanResetPromptBuilder` produceert ISO-gedateerde prompts met expliciete "heilige sessies"-sectie. ProgressView in de knop tijdens de API-call. 13 unit tests in `PlanResetPromptBuilderTests` + `TrainingPlanManagerMergeTests` dekken: prompt-format, heilige-sessies-vermelding, datum-mismatch in merge, lege AI-output, AI-overlap met swap, sortering, motivation-overname.
* **❌ Story 33.3 — Sociale Modus:** Afgesloten zonder eigen implementatie. Functioneel gedekt door 33.1b — wanneer de gebruiker `.social` als sessie-type kiest (handmatig of via classifier op de Strava/HK-titel), krijgt de coach `intent.coachingSummary` ("Sociale sessie — intensiteit volgt het tempo van de groep, niet een fysiologisch doel. Beoordeel niet op zone-discipline maar op mentaal herstel.") in de prompt-injectie. On-device-validatie liet zien dat dit afdoende is voor de coach-toon. Komt opnieuw op de roadmap als blijkt dat sociale ritten écht eigen logica nodig hebben (bv. een aparte UI-modus, andere TRIMP-multiplier, of expliciete Vibe Score-koppeling) — niet vóór die behoefte concreet is.
* **✅ Story 33.4 — Intentie vs. Uitvoering:** `IntentExecutionAnalyzer` (pure Swift) vergelijkt gepland sessietype + TRIMP met werkelijke uitvoering. Cascade: typeMismatch > overload > underload > match > insufficientData (±15% TRIMP-marge). Plan-type via `SessionClassifier.classifyByKeywords` (Optie B — geen schema-wijziging, geen Gemini-update). `IntentExecutionContextFormatter` produceert per verdict een coach-bruikbaar `[ANALYSIS — INTENT vs UITVOERING]`-blok met expliciete reactie-instructies (compliment bij match, herstel-suggestie bij overload, compensatie bij underload, structurele-caveat bij type-mismatch). Coach Comparison-kaart in `WorkoutAnalysisView` met state-afhankelijke kleur/icoon (✅ groen, ⚠️ oranje, 🔥 rood-oranje, 💧 blauw — alle SF Symbols). Match op kalenderdag via `[SuggestedWorkout].first(matching: ActivityRecord)`. 19 unit tests dekken cascade + 15%-grens + UI-tekst per verdict.

---

### ✅ Epic #35: Dynamische Gemini Model-Selectie in Settings

Configureerbare Gemini-modellen in Settings zodat we overbelasting kunnen ontwijken zonder een nieuwe app-release. Catalogus wordt geserveerd door de Cloudflare Worker (gelijk gebruikt patroon met `X-Client-Token`) — de iOS-app haalt geen modelnamen rechtstreeks bij Google op zodat we centraal kunnen valideren welke modellen we ondersteunen.

* **35.1 — Cloudflare Worker `/ai/models`:** endpoint live op de Worker, beveiligd met `X-Client-Token`. Aanvankelijk een statische catalogus, daarna ge-upgrade naar live `GET https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY` met server-side filter (`generateContent` support, alleen Gemini-familie), sorteer-heuristiek en 1u-cache via `caches.default`. Tests in `vibecoach-proxy/test/index.spec.js` (vibecoach-proxy PR #1 + #2, gedeployed).
* **35.2 — iOS Catalogus & AppStorage:** `AIModelCatalogService` fetcht via `Secrets.stravaProxyBaseURL/ai/models`; `AIModelAppStorageKey.primary` / `.fallback` houden de keuze bij. Defaults (match met productie vóór Epic #35): `gemini-flash-latest` + `gemini-flash-lite-latest`. Bij ongeldige opgeslagen keuze (gedepreciëerd model) valt de UI stil terug op de server-default.
* **35.3 — Dual-Picker UI:** Twee `Picker`-componenten ("Primair model" / "Fallback model") in `AIProviderSettingsView`. Initiële load toont een `ProgressView`-placeholder; pickers verschijnen pas zodra de Worker-fetch klaar is (live óf fallback). Bij netwerkfout valt de UI stil terug op `AIModelCatalog.builtInFallback`.
* **35.4 — ChatViewModel wiring:** `buildGenerativeModel` en `buildFallbackGenerativeModel` lezen de gekozen modelnamen uit `UserDefaults` via `AIModelAppStorageKey.resolvedPrimary()` / `.resolvedFallback()` i.p.v. hardcoded strings. Bestaande 503/429-waterfall blijft ongewijzigd.
* **35.5 — Unit + UI tests:** 12 cases voor `AIModelCatalogService` (happy path, HTTP errors, decoding, transport, headers, builtInFallback, AppStorage resolvers) + 3 XCUITests voor de pickers via `-UITestOpenAICoachConfig` launch-arg. PR's #185, #187, #188, #189.

**Resultaat:** dynamic model-catalogus live in productie, configureerbaar per gebruiker, automatisch synchroon met Google's beschikbare modellen via de Worker — zonder app-release nodig om nieuwe modellen toe te voegen of te depreciëren.

---

### ✅ Epic #36: Test Coverage Verhoging — Foundation Hardening

Authoritatieve coverage-meting in april 2026 toonde dat sleutel-services 0% dekking hadden ondanks dat hun testfiles bestonden — de eerdere README-claim van 63% bleek niet onderbouwd. Deze epic dichtte de hoogste-impact gaten en bracht de gemeten full-suite coverage naar **51.16%** (was effectief ~7-30%). Strategie: focus op pure logica met groot LOC-volume en/of klant-kritieke paden; UI-Views blijven beperkt door SwiftUI-testbaarheid.

**Eindresultaat per sub-task** (full-suite coverage = unit + UI tests, gemeten via `xcodebuild -enableCodeCoverage YES`):

| # | Doel | Voor | Na |
|---|---|---|---|
| 36.1 | `ProgressService` + `BlueprintGap` | 0% | **95.12%** |
| 36.2 | `FutureProjectionService` (+ Periodization unlock via pbxproj-fix) | 0% | **97.07%** |
| 36.3 | `APIKeyValidator` | 0% | **67.44%** |
| 36.4 | `ProactiveNotificationService` (pure logica geëxtraheerd) | 0% | **31.25%** |
| 36.5 | `FitnessGoal` enums + computed properties | 21% | **82.61%** |
| 36.6 | `KeychainService` (integratie tegen sim-Keychain) | 1.7% | **93.10%** |
| 36.7 | README + ROADMAP bijgewerkt met gemeten coverage | — | — |

**Sub-task details:**

* **36.1 — `ProgressService` + `BlueprintGap`:** 1-regel smoke-test vervangen door 41 cases die `TRIMPTranslator`, `BlueprintGap` computed properties en `ProgressService.analyzeGaps` (incl. fase-window TRIMP-accumulatie en sport-specifieke km-filtering) afdekken.
* **36.2 — `FutureProjectionService` + pbxproj-fix:** ontdekt dat 49 al-geschreven testcases nooit liepen door pbxproj-bugs (ontbrekende `PBXFileReference`-declaraties + niet-hex IDs). Fix + 16 nieuwe cases voor `coachContext` branches.
* **36.3 — `APIKeyValidator`:** error-classificatie geëxtraheerd naar `classify(_:)` static helper; 12 cases voor alle `GenerateContentError`/`URLError`-paden + input-guards.
* **36.4 — `ProactiveNotificationService`:** 4 pure helpers geëxtraheerd uit het stateful singleton (`composeEngineAContent`, `composeEngineBContent`, `isCooldownActive`, `banisterTRIMP`). Plafond op 31% omdat ~70% iOS-lifecycle is (`HKObserverQuery`, `BGTaskScheduler`) — alle door gebruiker zichtbare notificatie-tekst en cooldown-gate nu defended.
* **36.5 — `FitnessGoal` enums:** 38 nieuwe cases voor `SportCategory.from(hkType:/rawString:)`, `BodyArea.severityLabel`, alle enum displayName-mappings, `AIProvider.isSupported`, `SuggestedWorkout.resolvedDate` (NL/EN/ISO).
* **36.6 — `KeychainService`:** 11 integratietests tegen de echte simulator-Keychain met UUID-namespaced service-namen. CI-flake in een aanpalende test (`testSendMessage_WithInvalidAPIKeyError`) tegelijkertijd opgelost door fixed `Task.sleep` te vervangen door polling-loop.

**Lessons learned:**

- README-coverage-claims zonder authoritatieve meting zijn niet betrouwbaar — vóór deze epic was de werkelijkheid significant lager dan het geclaimde 63%.
- Pbxproj-fouten kunnen testfiles compleet doen verdwijnen zonder zichtbare error — de "0% coverage ondanks bestaand testfile"-symptoom is een red flag voor pbxproj-corruptie.
- iOS-lifecycle services (HealthKit observers, BG tasks, notification center) leveren een hard ceiling op coverage; de scheidslijn met pure logica moet bewust ontworpen worden om testbaarheid mogelijk te maken.

---

### 🔄 Epic #37: Internationalisatie & Engelstalige codebasis (NL + EN + DE + ES)

Twee samenhangende sporen, nu mét commitment en richting:
1. **App meertalig** — Nederlands (huidige basis) + **Engels, Duits, Spaans**, met de localisatie-infra (`Localizable.xcstrings`) zó opgezet dat een extra taal louter een kolom vertalingen is.
2. **Codebasis volledig Engelstalig** — alle code-comments, alle vier doc-files (README, ARCHITECTURE, ROADMAP, CLAUDE.md) én de in-code prompt-teksten naar Engels.

Cijfers hieronder zijn opnieuw gemeten op de huidige codebase (mei 2026; 127 Swift-files, ~28k LOC) — flink gegroeid t.o.v. de oorspronkelijke analyse.

**Kern-inzicht dat het zwaarste pad licht maakt:** omdat de codebase tóch naar Engels gaat, herschrijven we de AI system-instruction één keer naar Engels en geven het model een locale-afhankelijke **"respond in {language}"**-directive. We onderhouden dus géén vier vertaalde promptkopieën — de gegenereerde prose komt in de taal van de gebruiker, terwijl de instructie + statische context-labels Engels blijven (LLM's lezen die prima). Dat vervangt de oude "hele prompt per taal templaten"-aanpak.

#### 37.1 — Localisatie-infra + UI-strings

| Categorie | Inventaris | Aanpak |
|---|---|---|
| `Localizable.xcstrings` | 0 (nul-start) | String Catalog aanmaken; 4 talen-kolommen |
| SwiftUI string-literals (`Text`/`Label`/`Button`/`.navigationTitle`) | **291** | extraheren naar keys, `String(localized:)` |
| Notificatie-teksten (`ProactiveNotificationService`) | ~10 | gelocaliseerde keys |

Pure-Swift helpers die nu strings teruggeven (formatters) krijgen een `Locale`/key-parameter i.p.v. inline NL-tekst. **Effort:** ~22–30u.

**Gerealiseerd (✅, PR #291–#300):** String Catalog opgezet + taalkeuze in Settings (37.5) + locale-formattering (37.2) + runtime taalwissel (37.1a). Daarna de **`Text(String)`-sweep (37.1c)**: alle verbatim-renderende variabel-strings omgezet — `Text(LocalizedStringKey(var))` voor gedeelde rij/kaart-componenten, `String(localized:)` voor computed `-> String`-props. Gedekt: Settings, Dashboard, Goals, VibeScore, TrainingThresholds, GapAnalysis, WeekTimeline, WorkoutAnalysis, Onboarding, Sync/Blueprint/Trend-widgets, ChatView-coachkaarten + UI-only enums (Theme, phase-focus). ~482 catalog-keys EN/DE/ES. **Open:** sport-/sessie-type-namen (`SportCategory`/`SessionType.displayName`) + HR-zone + `GoalBlueprint.displayName` blijven bewust NL omdat ze in de coach-prompts geïnterpoleerd worden — die UI-vs-prompt-splitsing zit in **37.4**. UI-tests draaien sindsdien geforceerd in `nl` (`-testLanguage nl`) want de app is nu locale-gevoelig. Patroon + valkuilen vastgelegd in geheugen (`project_i18n_textvar_pattern`).

#### 37.2 — Locale-aware datum/getal-formattering

**28** plekken met hardcoded `Locale(identifier: "nl_NL")` → device- óf gekozen locale. Datumnamen, getallen en eenheden volgen de actieve taal. **Effort:** ~4–6u.

#### 37.3 — Meertalige AI-coach (kritiek pad, maar verlicht)

System-instruction in `ChatViewModel` (~90 regels) + ~19 context-formatters/prompt-bouwers + ~34 `Nederlands`/`nl_NL`-referenties. Aanpak conform het kern-inzicht:
- System-instruction + statische context-labels **naar Engels** (valt samen met 37.6).
- Locale-afhankelijke `respond in {language}`-directive (NL/EN/DE/ES) i.p.v. het harde "Reageer in het Nederlands".
- Dynamische waarden (datums, BPM, TRIMP, zones) via 37.2 locale-geformatteerd.
- JSON-respons-sleutels zijn al Engels — parser ongewijzigd; alleen de prose-velden (`motivation`/`description`/`reasoning`) komen voortaan in de gebruikerstaal.

**Effort:** ~12–16u (was 20–24u dankzij de één-prompt-aanpak).

#### 🔄 37.4 — Taal-afhankelijke detectielogica + UI-label-split

**Gerealiseerd (✅, PR #301):**
- **UI-label-split**: `SportCategory`/`SessionType.displayName`, `BodyArea.rawValue` en `severityLabel` blijven NL (prompt-gekoppeld / SwiftData-opslag), maar de View-render-sites resolven ze via `LocalizedStringKey` / `String.LocalizationValue` → de UI toont vertaald terwijl de prompt stabiel blijft. Sluit de bewuste gap uit 37.1c.
- **`BodyArea.injuryKeywords`** → NL+EN+DE+ES-union (accenten met/zonder diacriet); `SymptomContextFormatter` hergebruikt die set (DRY) + meertalige algemene blessure-woorden.
- **`SuggestedWorkout.resolvedDate`** → parseert nu ook Duitse + Spaanse dagnamen.
- Tests: DE/ES-dagnaam-parsing (incl. accent-varianten) + meertalige keyword-dekking.

**Open:** `BodyArea.severityLabel` blijft in de coach-*prompt* NL (alleen de UI-render is gelokaliseerd) — volledige prompt-taal valt onder 37.3.

Productie-logica die op NL-woorden leunt, wordt per-taal:
- **`BodyArea.injuryKeywords`** — blessure-keywords (`kuit`, `scheen`, …) → keyword-set per taal (NL/EN/DE/ES).
- **`BodyArea.severityLabel`** — pijnlabels → gelocaliseerd.
- **`SuggestedWorkout.resolvedDate`** — parseert dagnamen nu bilingual NL+EN; uitbreiden naar DE+ES (bestaand per-taal-lookup-patroon).

~21 detectie-hits. **Effort:** ~6–10u (vier keyword-sets + tests).

#### 37.5 — Taalkeuze in Settings

In-app taalkiezer die de device-locale overruled (default: device-locale, geen forced switch voor bestaande gebruikers). Propageert via `@Environment(\.locale)` + AppStorage; vraagt mogelijk een state-reload. **Effort:** ~6–8u.

#### 37.6 — Code-comments → Engels

| Metric | Aantal |
|---|---|
| Totaal comment-regels | **5.077** |
| Geschat % Nederlands | ~85% (~4.300 regels) |
| `// MARK:`-kopjes met NL/Epic-refs | tientallen |
| Variabel-/functienamen | al Engels (Swift-conventie) |

LLM-geassisteerd per file, in behapbare batches om git-blame-vervuiling te spreiden. **Geen runtime-impact** (review-only risico). **Effort:** ~30–40u.

#### 37.7 — Documentatie → Engels + projectregels omdraaien

README, ARCHITECTURE, ROADMAP, CLAUDE.md naar Engels, plus de afgeleide `architecture.json`/`.html`. **Belangrijk:** dit draait twee staande CLAUDE.md-regels om — §5 ("comments in het Nederlands") en §10 ("antwoord in het Nederlands") — die als onderdeel van deze epic naar Engels worden herschreven. **Effort:** ~16–24u.

#### 37.8 — Testsuite-i18n

UI-tests gebruiken nu hardcoded NL-assertions (`"Goedemorgen…"`, `"Doelen"`). Per taal een geforceerde locale-fixture (launch-arg `-AppleLanguages (xx)`) of assertions tegen localisatie-keys i.p.v. letterlijke tekst. **Effort:** ~12–16u.

#### Vertaalproductie

EN/DE/ES-vertalingen van ~291 UI-strings + notificaties: LLM-geassisteerd genereren in de xcstrings, daarna **native review** voor DE + ES (toon/idioom). **Effort:** ~16–24u.

#### Effort-overzicht

| Onderdeel | Uren |
|---|---|
| 37.1 infra + UI-strings | 22–30u |
| 37.2 locale-formattering | 4–6u |
| 37.3 AI-coach i18n | 12–16u |
| 37.4 detectielogica | 6–10u |
| 37.5 taalkeuze-UI | 6–8u |
| 37.6 comments → Engels | 30–40u |
| 37.7 docs → Engels + regels | 16–24u |
| 37.8 test-i18n | 12–16u |
| Vertaalproductie + native review | 16–24u |
| QA over 4 talen | 12–20u |
| **Totaal** | **~136–194u** (~4–6 sprints) |

#### Aanbevolen fasering (sprints)

1. **Engelse codebasis eerst** (37.6 + 37.7 + 37.3-prompt-naar-Engels). Levert direct een consistente Engelstalige basis op; de coach blijft functioneel (Engels) en het is de natuurlijke voorbereiding op i18n. Laag runtime-risico.
2. **i18n-fundament** (37.1 + 37.2 + 37.5): xcstrings, alle UI-strings geëxtraheerd, locale-formattering, taalkeuze-UI — met voorlopig alleen NL+EN gevuld.
3. **Coach + detectie meertalig** (37.3-directive + 37.4): respond-in-language + per-taal keyword-sets.
4. **Talen aanzetten** (vertaalproductie DE+ES + 37.8 test-i18n + QA): DE/ES-kolommen vullen, native review, locale-fixture-tests.

#### Blokkers en risico's

- **Coach-toon per taal** — `respond in {language}` werkt goed, maar DE/ES-toon manifesteert zich pas in productie; native steekproef aanbevolen vóór release.
- **Backwards-compat** — default blijft `Locale.current`; bestaande NL-gebruikers merken niets tot ze zelf een taal kiezen.
- **Git-blame** — 37.6 (~4.300 comment-regels) gespreid over batches/PR's om review behapbaar te houden.
- **CLAUDE.md-regelwijziging** — §5/§10 omdraaien raakt hoe de assistent zelf werkt; bewust expliciet in 37.7 zodat het geen sluipende inconsistentie wordt.

**Status:** ⏳ — gescoped en geprioriteerd (NL+EN+DE+ES + uitbreidbaar, coach in gebruikerstaal, hele codebasis + docs naar Engels). Nog niet gestart; klaar om sprint 1 (Engelse codebasis) op te pakken.

---

### ✅ Epic #38: HealthKit Permission UX & Sync Reliability

Aanleiding: een echte gebruiker (april 2026) deed een app-reinstall waarna iOS de HealthKit-toestemming gedeeltelijk reset had — Workouts/HRV/Cardio Fitness stonden uit. De auto-sync 'slaagde' technisch (HealthKit retourneert geen error bij gedeeltelijke permissies), maar haalde 0 workouts op. Resultaat: doelen op 0 TRIMP/0 km, banner "Bijsturing nodig", coach kende de atleet ineens niet meer. Stille faal — de slechtste UX. Deze epic vangt twee gerelateerde gaten af: proactief alle toestemmingen vragen, en zichtbaar maken wanneer de sync verdacht weinig oplevert.

* **✅ 38.1 — Bundle-permission-request:** Single source of truth in `HealthKitPermissionTypes` (`readTypes`, `writeTypes`, `critical`-subset). Beide bestaande auth-methodes op `HealthKitManager` (`requestOnboardingPermissions` + `requestAuthorization(completion:)`) lezen er nu uit — geen drift meer tussen "wat we vragen" en "wat we checken". `.activeEnergyBurned` toegevoegd (ontbrak voorheen). Nieuwe `requestPermissionsForCriticalNotDetermined()` async helper retriggert via `AppTabHostView.onChange(of: scenePhase)` op `.active`-transitie wanneer minstens één critical type (`workout`, `heartRate`, `hrv`, `activeEnergy`) `.notDetermined` is — alleen-`.notDetermined` mitigeert het risico van onverwachte prompts voor bestaande gebruikers.
* **✅ 38.2 — "Stille sync"-detectie + banner:** `HealthKitSyncService.syncHistoricalWorkouts(to:)` retourneert nu de workout-count uit het 365d-window; `AppTabHostView.runHealthKitAutoSync` en `SettingsView.runHealthKitHistoricalSync` cachen die naar `UserDefaults("vibecoach_lastHKWorkoutsCount")`. Pure-Swift `HealthKitSyncStatusEvaluator.shouldWarn(workoutCount:workoutAuthStatus:)` (4 unit tests) bepaalt de banner-conditie strikt: `count == 0 && authStatus != .sharingAuthorized`. Nieuwe `HealthKitPermissionWarningBanner` op `DashboardView` rendert via `DashboardBannerView`-wrapper (rood, `exclamationmark.icloud`-icoon, "Open Instellingen"-knop → `UIApplication.openSettingsURLString`). Gedeeltelijke toestemming (workouts wel, HR niet) is bewust buiten scope — manifesteert zich vanzelf in lege HR-grafieken.
* **✅ 38.3 — Reinstall-scenario:** Impliciet afgedekt via 38.1's `scenePhase = .active`-retrigger — bij elke foreground-return checkt de app of cruciale types `.notDetermined` zijn en vraagt alleen die opnieuw. Aparte `firstLaunchAfterInstall`-flag en eenmalige onboarding-tip uit de oorspronkelijke story bleken overbodig: het algemenere mechanisme dekt het reinstall-scenario én andere paden waarop iOS-toestemmingen `.notDetermined` worden (bv. Privacy & Security-reset).

**Effort gerealiseerd:** ~3u in één PR. 38.1 was een refactor + nieuwe helper (~1u), 38.2 een pure-Swift evaluator + nieuwe banner-component (~1u), 38.3 viel binnen 38.1 (~0u extra).

**Status:** ✅ — afgesloten (mei 2026). Bundle-permission, stille-sync-detectie en foreground-retrigger landen samen in één multi-story PR conform `feedback_epic_pr_workflow`. On-device validatie: reinstall-test met gedeeltelijke iOS-permissie-reset → banner verschijnt + `Open Instellingen` opent direct het juiste paneel.

---

### 🔄 Epic #39: Swift 6 Strict Concurrency Cleanup

Aanleiding: Xcode meldde 72 warnings rond actor-isolation in `ChatView.swift` en `FitnessDataService.swift` (april 2026). De warnings waren niet-blokkerend, maar Swift 6 (strict concurrency = complete) maakt ze tot harde compile-errors. Tech-debt om af te lossen voor we op een nieuwe Xcode/Swift-versie tegen een muur lopen.

**Sub-stories:**

* **✅ 39.1 — `Logger` static-properties cross-actor toegankelijk maken (70 warnings → 0):** `AthleticProfileManager.logger` zat als `static let` op een `@MainActor class` en was daardoor impliciet main-isolated; iedere reference vanuit een `@Sendable` HK-callback (HRV, slaap, slaapfases) gaf een warning. Nieuwe `AppLoggers`-enum (`Services/AppLoggers.swift`) bundelt loggers in een nonisolated namespace. `Logger` is intern thread-safe — actor-isolation eromheen voegt niets toe. Voor nu één entry (`athleticProfileManager`); volgende loggers migreren wanneer ze ook in de weg gaan zitten.
* **✅ 39.2 — `themeManager.primaryAccentColor` in `PhotosPicker`-label (2 warnings → 0):** De `PhotosPicker`-label-closure is `@Sendable` en mocht de main-actor-property niet direct lezen. Fix: kleur uitlezen in een lokale `let accentColor` vóór de closure, daarna `accentColor` capturen.
* **⏳ 39.3 — Project-instelling "Strict Concurrency Checking" naar `Complete`:** Optioneel — zou afdwingen dat toekomstige PR's geen nieuwe regressies introduceren. Niet meegenomen in deze cleanup omdat het mogelijk nieuwe Sendable-warnings boven water haalt die buiten de huidige scope vallen. Aparte follow-up wanneer de huidige cleanup een tijd stabiel is.

**Effort gerealiseerd:** ~1u. Pure type-system-tweaks; alle 542 tests blijven groen. Build gaat van 78 → 7 warnings (de 6 resterende zijn iOS 13-deprecations op `HKQuantitySeriesSampleQuery.init(sample:quantityHandler:)` — niet-concurrency, separate hygiene-PR).

**Status:** 🔄 — kern (39.1 + 39.2) live. 39.3 (build-setting promotion) wacht totdat we eventuele nieuwe warnings willen aanpakken als losse PR.

---

### ✅ Epic #40: Strava Power-Stream Ingest

Aanleiding: een gebruiker met Garmin powermeter (april 2026) ontdekte dat `cyclingPower` ontbrak in vibecoach hoewel zijn rides wél power tonen in Strava. Strava synct namelijk **geen** stream-data (power, cadence, velocity) naar Apple Health — alleen workout-events en gemiddelde HR. Daardoor mist de `WorkoutSample`-pijplijn (story 32.1) een hele klasse fietsdata.

**Sub-stories:**

* **✅ 40.1 — Strava `/streams` API-call:** `FitnessDataService.fetchActivityStreams(for:)` haalt `time`, `watts`, `cadence`, `heartrate`, `velocity_smooth` op via `?keys=...&key_by_type=true`. Token-flow hergebruikt bestaande Strava-OAuth.
* **✅ 40.2 — Deterministische UUID i.p.v. schema-wijziging:** `UUID.deterministic(fromStravaID:)` (SHA256, UUIDv5-achtig) leidt voor Strava-records een vaste UUID af. `WorkoutSample.workoutUUID` blijft `UUID` — geen migratie. `UUID.forActivityRecordID(_:)` is de centrale router (HK-uuidString of Strava-fallback).
* **✅ 40.3 — `StravaStreamIngestService`:** spiegel van `WorkoutSampleIngestService` (gescheiden om HK-logica niet te vervuilen). Hergebruikt `SampleResampler` met identieke strategieën (average voor HR/power/cadence, linear interpolation voor speed). Idempotent via `WorkoutSampleStore.replaceSamples`. Backfill in `DashboardView` scenePhase-flow voor de laatste 10 Strava-records zonder samples, met 100ms throttle. `WorkoutAnalysisView` gebruikt nu `UUID.forActivityRecordID` zodat de Strava-detail-view automatisch de power-chart toont zodra samples binnen zijn. Plus `StravaActivity.device_watts: Bool?` (decodeIfPresent — backwards-compat met bestaande caches). 14 unit tests.
* **✅ 40.4 — Classifier herclassificeert na stream-ingest:** `SessionReclassifier` (pure-Swift, mirror van `ActivityDeduplicator`-patroon) draait in dezelfde scenePhase-flow direct na de auto-dedupe. Records die net samples kregen (Strava-backfill 40.3 of HK DeepSync 32.1) krijgen het zone-distributie-voorstel; records zonder samples worden overgeslagen omdat de avg-HR-fallback al bij ingest draaide. Plus `ActivityRecord.manualSessionTypeOverride: Bool?` (lightweight migration) — gezet door `WorkoutAnalysisView.setSessionType` zodat een handmatige keuze nooit door de rerun overschreven wordt. `WorkoutSampleStore` kreeg een `samples(forWorkoutUUID:)`-getter (gesorteerd op timestamp). 6 unit tests.

**Status:** ✅ — alle vier sub-stories live. De pipeline van Strava-API → SwiftData-record → stream-backfill → dedupe → reclassify is end-to-end zelfregulerend; nieuwe rides krijgen automatisch een correct sessieType zodra hun samples binnen zijn.

---

### ✅ Epic #41: Dual-Source Single-Record-of-Truth

Aanleiding: tijdens on-device-validatie van Epic #40 (april 2026) bleek dat een Garmin-rit zowel via Apple Health (workout + HR, geen power) als via Strava (volledig met power) als losse `ActivityRecord` in SwiftData belandt. De bestaande `removeDuplicateRecords` debug-knop in Settings (`startDate + sportCategory` composite key) was bron-blind: HK-record overleefde, Strava-record (mét power!) werd verwijderd.

**Sub-stories:**

* **✅ 41.1 — Bron-aware dedupe-prioriteit:** `ActivityDeduplicator` (pure-Swift) groepeert records op composite key (startDate ±5s + sportCategory) en kiest binnen elke groep de "rijkste" via heuristiek: samples > deviceWatts > trimp > avgHR > stable tiebreaker. Auto-dedupe in `DashboardView.scenePhase`-flow direct na de Strava-stream-backfill — gebruiker hoeft niets te doen, de DB blijft zelfreinigend. 10 unit tests dekken alle paden + edge cases.
* **✅ 41.2 — `deviceWatts` op `ActivityRecord`:** Optionele `Bool?` toegevoegd (lightweight migration). Gevuld vanuit `StravaActivity.device_watts` in beide sync-paden (`AppTabHostView.performAutoSync` + `SettingsView.syncHistoricalData`). Voor HK-records `nil` (geen device-meta-info beschikbaar). Werkt als sterk signal voor de dedupe-heuristiek — zelfs vóór de stream-backfill weet de helper al welke record rijker zal zijn.
* **✅ 41.3 — OAuth-hardening (`ensureValidToken()`):** Centrale guard op `FitnessDataService` die vóór elke API-call het token checkt en bij (bijna-)expiry refresht via de proxy. Vijf interne callers (latest/byId/streams/recent/historical) routen nu via deze ene functie — een lege of ontbrekende access-token gooit `.missingToken` in plaats van een silent 401 verderop in de pijplijn. 4 nieuwe tests dekken fresh-token, refresh-bij-expiry, ontbrekend en lege token.
* **✅ 41.4 — Ingest-side preventie (`smartInsert`):** `ActivityDeduplicator.smartInsert(_:into:)` doet bij ingest een drie-laagse check: (1) source-id idempotent, (2) ±5s window cross-source vergelijking via `shouldReplace`, (3) reguliere insert. Een armer HK-record overschrijft nooit meer een rijker Strava-record met deviceWatts — ongeacht volgorde. Toegepast in `HealthKitSyncService`, `AppTabHostView` (Strava auto-sync) en `SettingsView` (Strava historical sync). Handmatige "Verwijder Dubbele Activiteiten"-knop in Settings (DEBUG) verwijderd — auto-dedupe + smart-ingest dekken beide kanten af. 8 race-tests in `SmartIngestRaceTests` borgen volgorde-onafhankelijkheid.

**Status:** ✅ — afgesloten (april 2026, PR #222). De gebruiker hoeft de dedupe-knop niet meer te gebruiken; smart-ingest voorkomt verarming aan de voordeur en auto-dedupe ruimt eventuele resten op tijdens de scenePhase-flow. Hiermee is Epic #42 (Always-on Dual-Source Sync) ontkoppeld — de dedupe-laag is robuust genoeg om beide bronnen continu naast elkaar te draaien.

---

### ✅ Epic #42: Always-on Dual-Source Sync

Aanleiding: na on-device-validatie van Epic #41 (april 2026) vroeg de gebruiker of HealthKit weer als primaire bron ingesteld kon worden. Antwoord: *technisch ja, maar dan stopt de Strava-fetch en mis je power voor nieuwe rides.* In `AppTabHostView.performAutoSync` (en `SettingsView.syncHistoricalData`) stond een if/else op `selectedDataSource`: als HK primair was, werd het Strava-pad volledig overgeslagen. Dat was een artefact uit de tijd dat één bron leidend moest zijn — sinds Epic #41 hebben we een dedupe-laag die meerdere bronnen aankan, dus de exclusiviteit van het toggle-gedrag was overbodig geworden.

**Sub-stories:**

* **✅ 42.1 — Decouple sync-paden van toggle:** `AppTabHostView.performAutoSync` en `SettingsView.syncHistoricalData` zijn opgesplitst in `runHealthKit*Sync()` + `runStrava*Sync()` helpers die concurrent draaien via `async let`. `selectedDataSource` wordt niet meer gelezen in de sync-laag. Cross-source duplicaten worden afgevangen door `ActivityDeduplicator.smartInsert` (Epic #41). Bij ontbrekende Strava-token wordt de auto-sync stil overgeslagen — geen elke-launch-noise in de console.
* **✅ 42.2 — Herdefiniëring semantiek naar bron-voorkeur:** Settings-sectie "PRIMAIRE DATABRON" hernoemd naar "BRON-VOORKEUR"; helper-tekst legt uit dat beide bronnen altijd syncen en de toggle alleen bepaalt welke bron de coach als eerste aanspreekt. Verbindingen-cards in Settings tonen "Voorkeur" / "Aanvullend" i.p.v. "Primair" / "Backup".
* **✅ 42.3 — Backwards-compat:** `@AppStorage("selectedDataSource")`-key + `DataSource`-enum cases + raw values ongewijzigd, dus bestaande gebruikers behouden hun toggle-stand zonder reset of herinlog-prompt.

**Effort gerealiseerd:** ~1u. 4 bestanden (AppTabHostView, SettingsView, README, ROADMAP). Alle 30 regression-tests groen.

**Status:** ✅ — afgesloten (april 2026). De gebruiker kan HK als bron-voorkeur kiezen zonder Strava-power te verliezen. Tiebreaker-bias in `ActivityDeduplicator` op basis van bron-voorkeur is bewust uit scope gehouden; pure-Swift helper blijft AppStorage-onafhankelijk en de huidige id-tiebreaker is deterministisch genoeg.

---

### ✅ Epic #43: UI Polish — Settings-status & Layout-consistentie

Aanleiding: tijdens on-device-gebruik (april 2026) viel op dat (a) de drie "Verbindingen"-cards in `SettingsView` (HealthKit, Strava, AI Coach) hardcoded sublabels (`"Primair · Live"`, `"Backup"`, `"Gemini"`) toonden die niet meegingen met de werkelijke connectie-staat of de bron-toggle, en (b) de "Goedenavond"-titel op `DashboardView` deels onder de iPhone-statusbar verdween terwijl de andere tabs (Settings, Doelen, Coach, Geheugen) die ruimte wel correct respecteerden.

**Sub-stories:**

* **✅ 43.1 — Dynamische Verbindingen-cards in Instellingen:** Drie computed properties in `SettingsView` (`healthKitConnectionSubtitle`, `stravaConnectionSubtitle`, `aiCoachConnectionSubtitle`) reflecteren nu de werkelijke state. HealthKit en Strava tonen "Primair"/"Backup" afhankelijk van `selectedDataSource`, of "Niet gekoppeld" wanneer de bron niet geauthoriseerd is. AI Coach toont de korte provider-naam (Gemini / OpenAI / Anthropic) en — alleen bij Gemini — ook het gekozen model uit Epic #35 (bv. "Gemini · flash-latest"). Geen wijziging aan `SettingsConnectionCard` zelf; binaire green/grey-dot blijft zoals 'ie was. Volwaardige tri-state (oranje voor partial-auth) komt mee met Epic #38 (HealthKit Permission UX).
* **✅ 43.2 — Dashboard-titel onder status bar fixen:** `DashboardHeaderView` ontbrak `.padding(.top, 56)` die alle andere tab-views (`SettingsView`, `GoalsListView`, `ChatView`, `PreferencesListView`) wel hadden. Eén regel toegevoegd; visuele hierarchy van de andere views ongewijzigd.

**Effort gerealiseerd:** ~30 min. 43.2 was een one-liner; 43.1 was drie computed properties + één extra `@AppStorage`-binding voor de Gemini-modelnaam. Geen nieuwe tests — bestaande 542-tests-suite blijft groen, en de logica in de computed properties is voldoende eenvoudig om visueel te verifiëren.

**Status:** ✅ — beide stories live. Eventuele tri-state-uitbreiding (oranje dot bij partial HealthKit-auth) volgt mee met Epic #38.

---

### ✅ Epic #44: Persoonlijke HR Zones & FTP

Aanleiding: tijdens on-device-validatie van Epic #32 story 32.3b (april 2026) bleek de `WorkoutPatternDetector` op een rustige sociale rit drie significante "rode" patronen te rapporteren (decoupling 102%, cardiac drift 13%, trage HR-recovery 11 BPM). De decoupling-bug is met een steady-state-CV-gate gerepareerd, maar het onderliggende probleem blijft: **alle drempels zijn populatie-gemiddelden** (Joe Friel / TrainingPeaks-norm + Tanaka maxHR), terwijl deze gebruiker hogere zones heeft dan een gemiddelde 35-jarige (zone 2 = 139–157 BPM). Een Z2-rit ziet er voor de detector uit als een Z3-effort en de Coach-analyse oordeelt te hard.

Naast de detector heeft FTP impact op `SessionClassifier` (zone-distributie-classificatie van power-data), `ChatViewModel.buildContextPrefix` (de coach moet "rustig" anders interpreteren voor deze gebruiker) en de coaching-toon in het algemeen.

**Sub-stories:**

* **✅ 44.1 — Foundation: `ThresholdValue` + zone-calculators (PR A):** `UserPhysicalProfile` uitgebreid met optionele `maxHeartRate`, `restingHeartRate`, `lactateThresholdHR` en `ftp`-velden — elk een `ThresholdValue { value, source }` met `ThresholdSource.automatic / manual / strava`. Backwards-compat via expliciete init met defaults. `effectiveMaxHeartRate` valt terug op Tanaka(`ageYears`) en `effectiveRestingHeartRate` op 60 BPM zodat alle bestaande consumers blijven werken. Persistence in `UserProfileService` via vier `vibecoach_*.v1` UserDefaults-keys + `cachedThreshold` / `saveThreshold` / `storeAutoDetectedThresholds`-helpers (laatste respecteert `manual` boven `automatic` standaard). Pure-Swift `HeartRateZoneCalculator` (Karvonen + Friel-LTHR, beide 5 zones) en `PowerZoneCalculator` (Coggan 7-zone-model met open Z7) leveren `[HeartRateZone]` / `[PowerZone]` met `zoneIndex`-lookup voor detector-gates.
* **✅ 44.2 — Automatische detectie uit HK-historie (PR A):** `PhysiologicalThresholdEstimator` (pure-Swift, AppStorage-vrij) leidt uit een verzameling `WorkoutHRSample` + dagelijkse rust-HR-samples drie drempels af: **max-HR** als hoogste 95e-percentiel over alle eligible workouts (>20 min, >30 samples, plausibility-filter 80-220 BPM), **rust-HR** als mediaan over plausibele dagelijkse HK-samples (30-100 BPM, minimum 14 dagen), **LTHR** als hoogste 30-min rolling-window-gemiddelde uit de zwaarste workout. Caller doet de HK-fetch zelf en geeft de samples mee — adapter-laag volgt in 44.4 wanneer de Settings-UI de detectie kan triggeren. 51 unit tests dekken zone-calculators, estimator, threshold-persistence en effective-fallbacks.
* **✅ 44.3 — Strava FTP-import (PR B):** `FitnessDataService.fetchAthleteFTP()` haalt FTP op via `/api/v3/athlete` met de bestaande OAuth — minimale `StravaAthlete`-DTO met alleen `ftp: Int?` (geen extra PII). Wordt door de Settings-UI aangeroepen om de FTP met source `.strava` op te slaan. Eigen detectie uit power-streams (klassieke 20-min-avg × 0.95) is bewust uit scope gehouden — Strava's eigen waarde wint en handmatige invoer wint van beide.
* **✅ 44.4 — Settings-UI + HK-adapter (PR B):** Nieuwe `TrainingThresholdsSettingsView` (NavigationLink-target onder "TRAININGSDREMPELS" in Settings) met vier rij-cards (Max HR / Rust HR / LTHR / FTP), per kaart bron-badge ("Auto · uit HK-historie", "Handmatig", "Strava"), edit-sheet met getalveld + wis-knop, twee actie-rijen ("Detecteer uit HK historie", "Importeer FTP van Strava"), en een live zone-preview-card onderaan (Friel-LTHR óf Karvonen voor HR; Coggan voor power). Adapter-laag `PhysiologicalThresholdService` wraps `PhysiologicalThresholdEstimator` met de daadwerkelijke HK-queries — workouts van afgelopen 6 maanden + dagelijkse `restingHeartRate`-samples, bucket-resampler naar 60s buckets voor LTHR.
* **✅ 44.5 — Detector- en classifier-kalibratie (PR C):** `WorkoutPatternDetector.detectCardiacDrift` en `detectHeartRateRecovery` accepteren een optionele `zones: [HeartRateZone]?`-parameter. Cardiac drift triggert alleen wanneer de avg-HR in Z1-Z3 valt (echte aerobic effort) — Z4/Z5-drift is verwacht gedrag. HR-recovery vereist een piek in Z3+ — recovery van een Z2-piek is geen informatief signaal. Nieuwe `detectAll(in:profile:)`-overload leidt zones uit `UserPhysicalProfile` af (Friel als LTHR aanwezig is, anders Karvonen) en threadt ze door. Backwards-compat default nil houdt populatie-globaal gedrag intact voor callers zonder profiel. `WorkoutAnalysisView` en `DashboardView.refreshWorkoutPatternsContext` gebruiken nu de profile-aware variant. `SessionClassifier` krijgt optionele `lactateThresholdHR`-init-parameter; `classifyByZoneDistribution` schakelt over naar Friel-percentages (<81/81-89/90-93/94-99/100+) wanneer LTHR aanwezig is.
* **✅ 44.6 — Coach-prompt-context (PR C):** Nieuw `[TRAININGSDREMPELS]`-blok in `ChatViewModel.buildContextPrefix` met max/rest/LTHR/FTP + bron-badges + expliciete Z2/Z3-grenzen ("Z2 = 142-158 BPM, Z3 = 158-165 BPM"). Gedragsregels in het blok: interpreteer "rustig" altijd in de context van deze drempels, koppel BPM-getal aan zone in subjectieve feedback, gebruik concrete grenzen bij plan-aanpassingen. Helemaal weglaten als geen drempels gezet zijn — dan blijft de coach z'n populatie-aannames hanteren.

**Effort gerealiseerd:** ~6-8u verdeeld over drie PR's (#226 / #229 / #230). 44.1 + 44.2 zijn pure-Swift + getest (~2u), 44.3 was ~30 min onderzoek + import-call, 44.4 was de grootste qua UX (~2u), 44.5 + 44.6 zijn refactors die tests bijwerken (~2-3u).

**Status:** ✅ — afgesloten (april 2026, PR #226 + #229 + #230). Gerealiseerd in drie PR's: foundation (`ThresholdValue` + zone-calculators + `PhysiologicalThresholdEstimator`), Strava FTP + Settings-UI + HK-adapter, en detector/classifier-kalibratie + coach-prompt-context. Op-device geverifieerd via de Epic #45-prompt-dump: het `[TRAININGSDREMPELS]`-blok wordt correct geïnjecteerd en de detector-gates respecteren het persoonlijke profiel — Z2-rides triggeren niet meer als false-positive significant patroon.

---

### ✅ Epic #45: Per-workout context in schema- en doelanalyse-prompt

Aanleiding: na Epic #44 worden persoonlijke trainingsdrempels (max/rest/LTHR/FTP + zones) al door `ChatViewModel.buildContextPrefix` in elke AI-call geïnjecteerd, en is er een 1-regel `workoutPatternsContext` voor de afgelopen 7 dagen ("Recente workout(s) tonen: aerobic decoupling, cardiac drift."). Voor schema-bouw en doelanalyse is die ene regel echter te dun — de coach kan er geen specifieke verwijzingen op baseren ("zoals in je drempelloop van afgelopen dinsdag…"). Met rijkere per-workout-context kan de AI beter onderbouwde plan-aanpassingen voorstellen.

**Sub-stories:**

* **✅ 45.1 — `WorkoutHistoryContextBuilder` (pure-Swift):** Bouwt een 1-regel-per-workout blok van de afgelopen 14 dagen — datum (NL-locale), sport, sessieType, duur, TRIMP, gem-HR, optioneel gem-W, en de detector-output als inline-suffix (severity + kind, hergebruik van `WorkoutPatternDetector.detectAll(in:profile:)`). Pure-Swift `enum` met geïnjecteerde `WorkoutEntry`-DTO's — caller (DashboardView) doet de async sample-fetch. Sortering nieuwste→oudste. Lege array → `""` zodat het hele blok wegvalt. 5 unit-tests in `WorkoutHistoryContextBuilderTests`.
* **✅ 45.2 — Injectie in `buildContextPrefix`:** Nieuw `[RECENTE TRAINING — 14 DAGEN]`-blok in de chat-context-prefix direct ná de 7d-pulse, met 5 gedragsregels: specifieke datum-verwijzingen, ≥3-opeenvolgende-patronen-trigger voor sub-LTHR-suggesties, alleen-bij-reflectie/schema/doelanalyse, zone-terminologie consistent met `[TRAININGSDREMPELS]`, en blessure-weging via `[ACTUELE KLACHTEN]`.
* **✅ 45.3 — Cache + refresh-consolidatie:** `@AppStorage("vibecoach_workoutHistoryContext")` cache in `ChatViewModel`. `refreshWorkoutPatternsContext()` is gerefactord naar gedeelde `refreshChatContextCaches()` die de loop over `activities` één keer draait en zowel de 7d-pulse als de 14d-rijke cache vult uit dezelfde `[WorkoutEntry]`-array — halveert SwiftData-fetch-I/O en voorkomt dubbele detector-calls.

**Tradeoff:** meer tokens per AI-call → iets hogere API-kosten en marginaal hoger safety-filter-risico (lange prompts kunnen zeldzaam content-blocked worden). Voor power-users die het schema serieus tunen weegt de winst (specifieke, onderbouwde adviezen i.p.v. generieke aannames) ruim op tegen de kosten.

**Status:** ✅ — geïmplementeerd op branch `feature/epic-45-workout-history-context` (3 stories in één PR conform `feedback_epic_pr_workflow`).

---

### ✅ Epic #46: GitHub Actions DAG-Visualisatie & Pipeline-Uitbreiding

Aanleiding: het GitHub Actions Summary-tabblad rendert een visuele DAG van jobs zodra een workflow uit meerdere jobs bestaat met `needs:`-relaties (zie referentie-screenshot van een full-stack web-app: Build → Tests → Deploy → Smoke). Op dit moment heeft VibeCoach één monolitische `Build & Test`-job in `ios-tests.yml` plus een losse `CodeQL`-workflow — geen visualisatie omdat er niets te chainen valt. Doel van deze Epic: de iOS-pijplijn opsplitsen in losgekoppelde jobs voor visueel inzicht en parallellisatie, zonder de complexiteit van signing/secrets binnen te halen. Backlog-stories houden zwaardere uitbreidingen (TestFlight, snapshot-tests, dependency-scan) zichtbaar voor het moment dat er concrete pijn ontstaat.

**Scope-keuze:** het screenshot toont een web-app pipeline met deploy-naar-acceptance/productie en Playwright. Dat patroon is niet 1-op-1 toepasbaar — App Store-distributie via TestFlight vraagt een Apple Developer-account, App Store Connect API-key en signing-certs in GitHub Secrets. Die staan in de backlog (46.B1), niet in de hoofd-scope.

**Sub-stories (laagdrempelig — geen extra secrets):**

* **✅ 46.1 — Splits `ios-tests.yml` in `unit-tests` + `ui-tests` jobs:** Twee aparte jobs op `macos-latest`. `unit-tests` draait `xcodebuild test` met `-only-testing:AIFitnessCoachTests`, `-enableCodeCoverage YES` en `-resultBundlePath UnitTests.xcresult`; bundle wordt geüpload via `actions/upload-artifact@v4` (`if: always()`, 7 dagen retentie) zodat zowel debugging-bij-falen als de coverage-job toegang heeft. `ui-tests` heeft `needs: unit-tests` en `-only-testing:AIFitnessCoachUITests`. Tradeoff: 2× macOS-runner-tijd per push, maar UI-falen kan geen unit-test-feedback meer vertragen. Tevens opgeruimd: duplicate `Setup Secrets`-step die op case-insensitive macOS toevallig werkte met verkeerde-casing pad (`Secrets-Template.swift`); `actions/checkout@v3` → `@v4` voor consistentie met `codeql.yml`. **Bijvangst:** UI-tests draaiden voorheen helemaal niet op CI — `AIFitnessCoachUITests` had `IPHONEOS_DEPLOYMENT_TARGET = 26.2` (Xcode-default, nooit verlaagd) waardoor `xcodebuild test` zonder `-only-testing` ze stilletjes oversloeg op een 18.x-simulator. Verlaagd naar 18.0 in `project.pbxproj` (matcht main app + unit tests; geen `@available iOS 26`-call sites). **UI-tests-job is hard-blocking** sinds 46.4 de root-causes onderscheiden heeft: parallel-disable elimineerde de runner-clone-flakiness en de overgebleven 3 failures bleken test-code-bugs (verborgen V2.0 NavigationBar, `.textField` lookup voor SwiftUI's `.textView`-rendering, te-korte timeouts). `xcodebuild test` draait sequentieel (`-parallel-testing-enabled NO`); `-resultBundlePath UITests.xcresult` + CoreSimulator-logs blijven als artifacts beschikbaar voor toekomstige debug.
* **✅ 46.2 — Parallele `lint`-job (SwiftLint):** Twee-staps-aanpak gerealiseerd. **Prep-PR `chore/swiftlint-cleanup` (#246)** legde `.swiftlint.yml` aan en loste bestaande violations op: SwiftLint v0.63.2 dry-run gaf 938 violations (460 line_length, 171 identifier_name, 78 comma, 54 colon, …). Config disabled noisy stijl-rules die in deze codebase geen waarde toevoegen (line_length / identifier_name / *_length-rules / cyclomatic / multiple_closures_with_trailing_closure / large_tuple etc). `swiftlint --fix` deed 209 auto-fixes; resterende 4 (3 for_where + 1 unused_optional_binding) handmatig opgelost. **0 force-unwrap-rules** in deze prep — 77 violations zou een aparte audit-PR (`chore/force-unwrap-audit`) vragen omdat het meeste benign idiom is. **Lint-job-PR `feature/epic-46-swiftlint-job`** voegt `lint`-job toe aan `.github/workflows/ios-tests.yml` zonder `needs:` (draait parallel aan unit-tests) op `macos-latest` (SwiftLint pre-installed). `swiftlint --strict --reporter github-actions-logging` upgrade warnings naar errors zodat 1 nieuwe violation CI breekt; `github-actions-logging` reporter geeft inline annotations op het PR-diff.
* **✅ 46.3 — `coverage-report`-job als PR-artifact:** Hangt aan `needs: unit-tests` en downloadt de `UnitTests.xcresult`-bundle uit 46.1. Draait `xcrun xccov view --report --json` en transformeert via `jq` naar een per-target markdown-tabel (filtert `*Tests.xctest`-bundles weg). Upload als `coverage-report`-artifact met 30 dagen retentie. PR-comment-injectie is bewust niet meegenomen — vereist `pull-requests: write`-permissie en is makkelijk later toe te voegen wanneer we de markdown-output willen escaleren.
* **✅ 46.4 — UI Tests CI-flakiness root-cause-onderzoek:** Twee oorzaken onderscheiden via xcresult-artifact-analyse op `ci/investigate-uitest-flakiness`. **(1) Runner-clone-flakiness** — `AIFitnessCoachUITests.xctest` had `parallelizable = "YES"` in het scheme, xcodebuild spawnde meerdere xctrunner-clones (zichtbaar als "Clone 2 of iPhone 16 Pro" in logs) en de clone-spawning gaf intermitterend `ipc/mig server died` (Mach-308). 4 tests vlokten random. Fix: `-parallel-testing-enabled NO` op CI-niveau (scheme-config blijft `YES` voor lokale snelheid). Resultaat: 4 flaky tests → 0. **(2) Test-code-bugs** — drie tests faalden deterministisch, bleek geen runner-issue maar bestaande bugs die nooit eerder opvielen omdat UI-tests vóór 46.1 stilletjes overgeslagen werden door de iOS 26.2 deployment-target-mismatch. Fixes: `testNavigateToSettingsTab` zocht `app.navigationBars` in een view die V2.0 `.toolbar(.hidden)` heeft → vervangen door `SettingsVersionLabel`-identifier. `testCoachMemory` zocht `.textField` voor SwiftUI's `TextField(axis: .vertical)` die als `.textView` rendert → vervangen door `.any` element-matching. `testNavigateToCoachTab` had 8s timeout op een view waarvan `onAppear` SwiftData/AppStorage caches refresht → verhoogd naar 20s (en `testCoachMemory` naar 15s) voor CI-launch-tijd. Diagnose-tooling (xcresult artifact, CoreSimulator logs) blijft in de workflow voor toekomstige debug. **Eindresultaat:** `continue-on-error: true` verwijderd uit ui-tests job; UI-tests blokkeren nu echt CI bij regressies.

**Backlog (zichtbaar houden, geen toezegging):**

* **⏳ 46.B1 — TestFlight-deploy job op merge naar main:** `deploy-testflight`-job met `needs: [unit-tests, ui-tests]` en `if: github.ref == 'refs/heads/main'`. Vereist eenmalige setup: Apple Developer-account, App Store Connect API-key (`.p8`), signing-cert + provisioning-profile in GitHub Secrets, en `fastlane match` of `xcodebuild -exportArchive` met `ExportOptions.plist`. Effort: ~4–6u eenmalig voor cert-setup + workflow-syntax, daarna onderhouds-vrij. Pickup-trigger: gebruiker wil App Store Connect TestFlight-flow automatiseren i.p.v. handmatig archive uploaden.
* **⏳ 46.B2 — Snapshot-tests via `swift-snapshot-testing`:** PointFree's library voor view-snapshots (PNG-diff op kritieke schermen: Dashboard, Goals, Chat, Settings). Job `snapshot-tests` met `needs: unit-tests`. Eerste run genereert reference-images die in repo gecheckt worden; daarna faalt CI op visuele regressies. Effort: ~6–8u (library integreren + 5–10 reference snapshots schrijven). Pickup-trigger: een UI-regressie die door bestaande XCUITests niet werd gevangen.
* **⏳ 46.B3 — Dependency vulnerability scan:** GitHub `dependency-review-action` op PR's die `Package.swift`/`Package.resolved` raken. Vergelijkt nieuwe transitive deps met de GitHub Advisory Database. Effort: ~30 min. Pickup-trigger: Swift Package Manager wordt actief gebruikt voor third-party deps (op dit moment minimaal — alleen bestaande Anthropic/Strava-koppelingen via REST).
* **⏳ 46.B4 — Performance regression checks:** Build-tijd-tracking (`xcodebuild`-output parsen) en/of een lichte `XCTMetric`-baseline (launch-tijd, dashboard-render) als eigen job met historisch artifact-vergelijk. Effort: ~4u. Pickup-trigger: gebruiker meldt subjectieve traagheid en we willen objectieve baselines.
* **⏳ 46.B5 — Concurrency-strict-build als matrix-cel:** Voortbouwend op Epic #39 story 39.3 — een matrix-cel die met `SWIFT_STRICT_CONCURRENCY=complete` bouwt zodat nieuwe Sendable-warnings als CI-fail naar boven komen, zonder de hoofd-build te breken. Effort: ~1u zodra 39.3 zelf gedaan is.
* **⏳ 46.B6 — Semver-versioning via `release-please` + git-tag-gebaseerde `MARKETING_VERSION`:** Release-mechaniek, onafhankelijk van 46.B1 bruikbaar (tag + GitHub Release hebben los waarde als release-historie). Drie sub-stappen: (1) `googleapis/release-please-action` workflow op main; bot opent een Release PR die accumuleert tot jij 'm mergt — bij merge wordt automatisch de git tag (`v1.2.3`) + GitHub Release met changelog aangemaakt. Patch/minor/major afgeleid uit Conventional Commits-prefixen (`fix:` / `feat:` / `feat!:`). (2) Run Script Build Phase die `CFBundleShortVersionString` bij build-tijd uit `git describe --tags --abbrev=0` zet, parallel aan de bestaande `CFBundleVersion = git rev-list --count HEAD`-aanpak. Eén source of truth (de tag), geen `MARKETING_VERSION`-mutatie in `project.pbxproj` nodig — dat bestand houdt z'n `skip-worktree`-flag (CLAUDE.md §9). (3) Conventional Commits formaliseren in CLAUDE.md §8 als harde regel — wordt al gevolgd in de praktijk, maar release-please vertrouwt op consistentie. Effort: ~2-3u eenmalig. Pickup-trigger: eerste echte release (TestFlight friendly-users of App Store), of eerder als je release-historie expliciet wil maken voordat de eerste release uitgaat.

**Effort gerealiseerd (46.1 + 46.2 + 46.3 + 46.4):** ~7u — 46.1+46.3 in PR #244 (~3u, waarvan ~2u eerste-pass UI-tests-debugging), 46.4 in PR #245 (~2u, datagedreven xcresult-analyse + 3 test-fixes), 46.2 in PR #246 (prep, ~1.5u) + lint-job-PR (~30 min).

**Status:** ✅ — alle hoofd-scope stories (46.1–46.4) live. Backlog-stories (46.B1–B6) blijven beschikbaar voor pickup wanneer hun trigger ontstaat.

---

### ✅ Epic #47: Pauze-gebaseerde HR-recovery

Aanleiding: tijdens on-device-validatie van een 2-uur fietsrit (mei 2026) rapporteerde `WorkoutPatternDetector.detectHeartRateRecovery` "4 BPM drop in 60s na piek" terwijl op de grafiek een duidelijke dip van ~40 BPM zichtbaar was tijdens een korte stop. Root-cause: de detector pakt de globale piek en meet HR exact 60s later — bij continue rides was de gebruiker op dat punt al weer aan het trappen, dus de dip *binnen* het window valt buiten het meetpunt. De metriek meet effectief "hoe snel ging je HR weer omhoog na een korte dip" i.p.v. "hoeveel daalde hij". Bovendien is HR-recovery fysiologisch alleen interpreteerbaar wanneer er daadwerkelijk rust valt (cool-down, koffie-stop) — niet bij een willekeurige spike midden in een continue effort. De Coach-analyse hing in dit geval een speculatief verhaal over vermoeidheid/hitte/ziekte aan een non-event.

Oplossingsrichting: vervang globale-piek-+-60s door **pauze-gebaseerde detectie**. Een pauze (power+cadence beide ≈ 0 voor ≥45s) is het natuurlijke window om parasympatisch herstel te meten. Drempels worden gekoppeld aan persoonlijke LTHR (15% LTHR-drop in 60s = uitstekend) i.p.v. absolute BPM, conform de Epic #44-filosofie van persoonlijke kalibratie. Bij meerdere pauzes pinnen we de slechtste recovery (Management by Exception §1). Goede recovery-events worden niet gepind maar wél als context naar de coach-prompt geïnjecteerd zodat de AI positief kan framen wanneer er expliciet naar gevraagd wordt.

**Sub-stories:**

* **✅ 47.1 — `PauseDetector` (pure-Swift):** Nieuwe `Services/PauseDetector.swift` met `PauseRecoveryEvent`-struct (pauze-range, hrAtStart, minHRInWindow, drop). Detecteert aaneengesloten samples waar `power < 5 && cadence < 5` (nil als ontbrekend signal) voor ≥45s. Pre-check: workout moet ≥10 samples met activiteit hebben (anders onbruikbaar — denk swimming zonder cadence-sensor). Recovery-window per event = `min(60s, pauze-duur)` — Optie A uit het ontwerp, eerlijk voor pauzes 45-60s.
* **✅ 47.2 — `detectHeartRateRecovery` herschrijven:** Vervangt globale-piek-+-60s door iteratie over `PauseDetector.detect(in:)`-output. Drempels relatief aan `referenceHR`-parameter: ≥15% = uitstekend (geen pin), 12-15% = mild, 9-12% = moderate, <9% = significant. Cascadende fallback `referenceHR ?? 165`. Bij meerdere pauzes wint de pauze met de laagste ratio. Detail-tekst toont pauze-duur expliciet ("12 BPM drop in pauze van 1:15").
* **✅ 47.3 — `referenceHR` doorroutering:** `detectAll(in:zones:referenceHR:)` als nieuwe overload; `detectAll(in:profile:)` leidt referenceHR af via nieuwe helper `referenceHeartRate(from:)` (LTHR voorkeur, anders 0.88 × maxHR, anders nil). De `zones`-parameter blijft alleen voor cardiac-drift-gating; recovery hangt enkel op `referenceHR`.
* **✅ 47.4 — Coach-prompt-context (Epic #45-haakje):** `WorkoutInsightService.InsightContext` krijgt `recoveryEvents: [RecoveryEventSummary]`-veld. `buildPrompt` voegt regel "Recovery-context: in pauze van X min daalde HR Y BPM (label)." toe wanneer events aanwezig zijn — ook positieve. Coach kan dan op verzoek positief framen ("je autonome zenuwstelsel reageerde uitstekend") zonder dat het dashboard een pin toont. Caller `WorkoutAnalysisView` roept `PauseDetector.detect(in:)` apart aan voor de InsightContext-payload.
* **✅ 47.5 — Tests:** Nieuwe `PauseDetectorTests` (verkeerslicht-stop 30s = niet-detecteerbaar, 90s pauze = wel, jitter, samples zonder power-stream-fallback, pauze tegen einde van workout, swimming-fallback waar pre-check faalt). `WorkoutPatternDetectorTests`: oude HR-recovery-tests herschrijven naar pauze-scenario (continue rit zonder pauze = geen pin, pauze-met-trage-recovery = pin met juiste severity, meerdere pauzes laagste ratio wint, LTHR/maxHR-fallback/absolute-fallback paden). Bestaande zone-gate-tests vervallen — vervangen door referenceHR-equivalenten.
* **✅ 47.6 — Doc-updates:** `ARCHITECTURE.md` sectie "HR-recovery via pauze-detectie" met de waarom-redenering (post-effort vagaal herstel vereist rust-window, anders meet je iets anders dan je denkt). ROADMAP-status van 🔄 → ✅ bij merge.

**Tradeoff:** workouts zonder pauze (interval-tests, korte tempo-loops) krijgen geen HR-recovery-pin meer — correct gedrag, want zonder rust-window kun je geen recovery meten. De cardiac-drift-detector vangt vermoeidheids-signalen op die zich anders manifesteren (HR-stijging tussen helften bij gelijke intensiteit), dus we verliezen geen detection-laag.

**Status:** ✅ — geïmplementeerd op `feature/epic-47-pause-based-hr-recovery`. Alle 730 unit-tests groen, inclusief 13 nieuwe `PauseDetectorTests` en herschreven HR-recovery-scenarios. Wacht op on-device validatie + merge.

---

### ✅ Epic #48: Coach-analyse koppelt aan doelen + periodisering

Aanleiding: na Epic #47 toont de Coach-analyse-tegel altijd een korte uitvoerings-bevestiging — ook bij ritten zonder patterns (positieve framing). Maar de tekst staat los van de bredere context: *waarom* deed je deze rit? Past hij in je Build-fase voor de marathon? Tikt 'ie een long-run-mijlpaal aan? Op het Dashboard heeft de chat-coach al toegang tot doel-status (`BlueprintContextFormatter`) en periodisatie (`PeriodizationResult.coachingContext`) via `ChatViewModel.cacheActiveBlueprints` / `cachePeriodizationStatus`. Diezelfde infrastructuur willen we per workout meegeven aan de `WorkoutInsightService` zodat de Coach-analyse expliciet de brug slaat naar het doel.

**Sub-stories:**

* **✅ 48.1 — `InsightContext` uitbreiden:** Twee optionele velden bij `WorkoutInsightService.InsightContext`: `goalsContext: String?` (output van `BlueprintContextFormatter.format(results:)`) en `periodizationContext: String?` (joined `PeriodizationResult.coachingContext`-blokken). Bij geen actief doel of geen blueprint blijft het veld nil en valt het blok in de prompt weg.
* **✅ 48.2 — `WorkoutAnalysisView` bouwt de context:** `@Query` voor `FitnessGoal` (active filter), `ActivityRecord`, `DailyReadiness` (latest). Roep `BlueprintChecker.checkAllGoals(goals, activities:)` en `PeriodizationEngine.evaluateAllGoals(goals, activities:, latestReadinessScore:)` aan, formatteer met de bestaande helpers en geef de strings mee aan `InsightContext`. Hergebruikt exact dezelfde infrastructuur die de chat-coach gebruikt — geen duplicate format-logica.
* **✅ 48.3 — `buildPrompt` + system-instruction:** Twee nieuwe blokken in de prompt: `[DOELEN-STATUS]` en `[PERIODISERING]`, alleen als de strings niet leeg zijn. System-instruction krijgt regel 5: "Verbind de uitvoering expliciet met het doel en de huidige fase wanneer aanwezig — bijv. 'past in je Build-fase voor de marathon, en deze 32km nadert je 28km long-run-mijlpaal'. Geen actief doel = niet noemen." Stijl-clausule blijft 3 zinnen max; coach kiest het meest relevante verband.
* **✅ 48.4 — Cache-key uitbreiden met goals-fingerprint:** Huidige cache-key is `pattern-fingerprint + profile-fingerprint`. Toevoegen: `goals-fingerprint` (hash van actieve doel-IDs + milestone-status + periodisatie-fase per doel) zodat een nieuwe doel-status (milestone behaald, fase-overgang) automatisch een nieuwe Coach-analyse triggert in plaats van een verouderde framing uit de cache te serveren.
* **✅ 48.5 — Tests + docs:** Nieuwe `WorkoutInsightServiceTests` voor de uitgebreide prompt-bouw (bevestigt dat `[DOELEN-STATUS]` + `[PERIODISERING]` worden meegestuurd wanneer beschikbaar, en weggelaten worden bij nil). ARCHITECTURE.md §10 (Workout Pattern Detection) krijgt een korte update over de uitgebreide insight-context.

**Tradeoff:** meer tokens per AI-call → iets hogere API-kosten. Voor power-users die actief doel-gericht trainen weegt de winst (specifiekere, doel-bewuste framings i.p.v. losse rit-observaties) ruim op tegen de kosten. Workouts zonder actief doel of zonder blueprint vallen automatisch terug op het pre-Epic-#48 gedrag.

**Status:** ✅ — gemerged via PR #258. On-device gevalideerd: coach legt nu één concrete koppeling met de actieve fase/mijlpaal i.p.v. een losse rit-observatie.

---

### 🔄 Epic #49: HK weather-metadata in Coach-analyse

Aanleiding: bij een drempelsessie of warme rit vraagt de coach vaak naar hitte als verklaring voor drift/decoupling — terwijl HealthKit de werkelijke temperatuur en luchtvochtigheid tijdens de workout al opslaat in `HKMetadataKeyWeatherTemperature` / `HKMetadataKeyWeatherHumidity` zodra de iPhone aanwezig was. Doel: die metadata uitlezen en aan de coach-prompt meegeven, zodat de coach hitte/luchtvochtigheid mee kan wegen i.p.v. ernaar te vragen.

**Sub-stories:**

* **✅ 49.1 — `ActivityRecord` uitbreiden:** Twee optionele velden — `temperatureCelsius: Double?` en `humidityPercent: Double?`. Pure addition, dus geen schema-versie-bump nodig (SwiftData lightweight migration).
* **✅ 49.2 — HK ingest-pad:** Nieuwe `HealthKitSyncService.extractWeather(from:)`-static-helper leest `HKMetadataKeyWeatherTemperature` (Apple gebruikt degF; converteer expliciet naar Celsius) en `HKMetadataKeyWeatherHumidity` (kan 0-1 of 0-100 zijn; normaliseer op 0-100). Defensief tegen wrong-type-values en ontbrekende keys → nil zonder crash.
* **✅ 49.3 — Coach-prompt:** `WorkoutInsightService.InsightContext` krijgt `temperatureCelsius` + `humidityPercent`. `buildPrompt` voegt `[WEER TIJDENS WORKOUT]`-blok toe wanneer ten minste één veld gevuld is. System-instruction krijgt regel: "weeg temperatuur >25°C of luchtvochtigheid >70% expliciet mee als verklaring voor drift/decoupling — vraag er niet meer naar". Geen blok = val terug op generieke aannames.
* **✅ 49.4 — Cache-key:** `WorkoutAnalysisView` cache-fingerprint krijgt `weatherFingerprint` zodat een DeepSync of latere ingest-update de Coach-analyse opnieuw genereert met de bijgewerkte hitte-context.
* **✅ 49.5 — Tests + docs:** `HealthKitWeatherExtractionTests` (9 tests) borgt unit-conversie + edge-cases (missing/empty/wrong-type). ARCHITECTURE.md §10 update over de weer-context.

**Tradeoff:** alleen workouts waar de iPhone aanwezig was hebben metadata. Strava-only ritten en oude HK-records zonder weer blijven zonder context — de coach valt daar terug op generieke aannames. Bij blijkende behoefte volgt later een Epic met GPS + historische weer-API als fallback.

**Status:** 🔄 — geïmplementeerd op `feature/epic-49-weather-metadata`. 743 unit-tests groen. Wacht op CI + on-device validatie + merge.

---

### 🔄 Epic #50: Open-Meteo historisch weer voor Garmin-/fietscomputer-only ritten

Vervolg op Epic #49 (HK weather-metadata). Garmin/fietscomputer-only wielrensessies hebben geen iPhone-tegenhanger in HK, dus `HKMetadataKeyWeather*` ontbreekt en de cross-source merge uit #49 levert niets op. Met Strava's `start_latlng` + `startDate` kunnen we Open-Meteo's archive-API bevragen voor historische temperatuur/luchtvochtigheid op die specifieke locatie en tijd.

**Sub-stories:**

* **✅ 50.1 — Strava DTO uitbreiden:** `start_latlng: [Double]?` toegevoegd aan `StravaActivity`. Strava levert het als `[lat, lng]` array; lege array (indoor/manual) wordt naar nil genormaliseerd voor coherent "geen locatie"-signaal.
* **✅ 50.2 — `HistoricalWeatherService`:** Pure-Swift met geïnjecteerde `WeatherURLFetcher` (testbaar zonder echte HTTP-call). Bouwt URL voor archive-API (>5 dagen oud) of forecast-API met `past_days` (recenter). Privacy: GPS-coords afgerond op 0.1° (~11km) vóór API-call. Hour-bucket-extractie matcht het uur dichtst bij de workout-startdate. Faalt graceful — bij netwerk-/API-fout krijgt caller `(nil, nil)`.
* **✅ 50.3 — Strava ingest-integratie:** Nieuwe `enrichRecord(_:from:startDate:)`-extension op de service. Aangeroepen in `AppTabHostView.performAutoSync` (auto-sync, max 14 calls) en `SettingsView.runStravaHistoricalSync` (1-jaar-knop, ~50-100 calls). Idempotent — slaat over als record al weer-data heeft (bijv. via Epic #49 cross-source merge). Combineert met Epic #49: bestaande HK-cross-source merge wint waar mogelijk; Open-Meteo vult de rest aan.
* **✅ 50.4 — Tests:** `HistoricalWeatherServiceTests` (11 tests): privacy-rounding, archive-vs-forecast-URL-keuze, hour-bucket-matching, graceful handling van Open-Meteo-`null`-waarden, fout-paden (invalid coords, out-of-range date, niet-2xx response), end-to-end met mock-fetcher.

**Privacy-overweging:** Open-Meteo logt geen request-IPs en is open-source, maar we sturen alsnog GPS-coords erheen. Door af te ronden op 0.1° (~11km radius) lekken we geen exacte locatie — voor weer-classificatie ruim genoeg (temperatuur-gradient over 11km is meestal <1°C).

**Tradeoff:** ~10s extra op de "Sync historische data"-knop voor 100 ritten (sequentieel). Auto-sync-impact verwaarloosbaar (max 14 calls per run). Open-Meteo gratis-tier dekt 1000 calls/dag — ruim binnen budget voor één gebruiker.

**Status:** 🔄 — geïmplementeerd op `feature/epic-50-historical-weather`. 769 unit-tests groen. Wacht op CI + on-device validatie + merge.

---

### 🔄 Epic #51: Foutmeldingen, validatie & zichtbaarheid (user-feedback hardening)

Aanleiding: systeemanalyse vanuit het gebruikersperspectief (drie parallelle audits op coach-chat, settings/forms en data-laag → UI-fout-propagatie) legde een serie unhappy flows bloot waar de app stille fouten, ontbrekende validatie of verwarrende feedback geeft. Niet kapot — wel in conflict met het Management-by-Exception-principe. Volledige scope + acceptatiecriteria per sub-story in [issue #265](https://github.com/markclausing/vibecoach/issues/265).

**Functionele groepering** (elk een eigen PR):

* **🔄 51.A — Coach-gesprek (deels):**
  - **✅ A1 + A5:** `ChatScopeInstruction` plakt een expliciete scope-restrictie bovenaan de system-prompt (coach weigert off-topic-vragen met vaste framing); `ChatErrorMessageMapper` (pure-Swift) vervangt de generieke "tijdelijk probleem"-melding door specifieke teksten per fout-categorie — offline / timeout / DNS / cancelled / safety-block / invalid-key / overbelast / generiek. 17 unit-tests. Gemerged via PR #269.
  - **🔄 A2 + A3 + A4 + A6:** `ChatModelSwitchNotice` toont een banner bovenaan de chat zodra de gebruiker tijdens `isTyping` van Gemini-model wisselt in Settings (huidig antwoord komt nog van vorig model, volgende vraag gebruikt het nieuwe — `_modelBuiltForName`-cache zorgt voor automatische rebuild zonder dat de gebruiker opnieuw moet inloggen). `ChatConversationTrimmer` (generic, pure-Swift) splitst lange gesprekken in een ingeklapt archief (>50 berichten) + zichtbare staart — UI-only optimalisatie omdat de chat-API geen message-history meestuurt. `ChatInputValidator` clampt paste-acties op 5000 tekens met een counter vanaf 80% en een eenmalige toast bij truncatie — voorkomt 45s-timeouts bij grote tekstblokken. Request-cancel via een `currentRequestTask`-handle in `ChatViewModel` + `cancelOngoingRequest()` op `ChatView.onDisappear` — een `CancellationError` veroorzaakt geen foutbubble of banner, alleen een `isTyping = false`. 28 unit-tests over de drie helpers.

  *Provider-switch was in de issue ruimer gespecificeerd (Gemini ↔ OpenAI ↔ Anthropic) — in deze codebase blijft de app Gemini-only, dus A2 implementeert de model-switch (primary ↔ fallback Gemini-model) en niet een cross-provider-switch. Cross-provider zou een eigen Epic vragen.*
* **⏳ 51.B — Doelen aanmaken & beheren:** datum minstens +7 dagen, realistische stretch-tijden per sport, titel-trim, soft-delete tegen stale coach-context
* **✅ 51.C — Profiel & trainingsdrempels:** `PhysiologicalThresholdValidator` (pure-Swift, AppStorage-vrij) doet live range-checks + cross-validatie (Max HR > Rust HR, LTHR < Max HR, LTHR > Rust HR). `ThresholdEditSheet` toont inline warnings/errors en disablet Opslaan bij fysiologisch inconsistente combinaties. Round-trip-check op `applyManualEdit` detecteert opslag-failures. `zonePreviewCard` toont context-bewuste uitleg waarom HR/power-zones ontbreken (welk veld nog vereist is, of welke cross-error de berekening blokkeert) i.p.v. een generieke "stel drempels in"-tekst. 17 unit-tests. Gemerged via PR #268.
* **⏳ 51.D — AI-provider & API-sleutel:** auto-trim bij plakken, prefix-detectie voor verkeerde provider, test-feedback persistent
* **⏳ 51.E — Onboarding & toestemmingen:** HealthKit als vereist, notificaties als optioneel, status-banner bij skip, achteraf-intrekken-detectie, status-overzicht in Settings
* **🔄 51.F — Data syncen (deels):**
  - **🔄 F1 + F2 + F5:** `SyncStatusStore` houdt per data-source de laatste succes-timestamp en de laatste fout-categorie bij; `SyncBannerStateBuilder` (pure-Swift) bepaalt op basis van een snapshot welke banner getoond wordt — prioriteit offline > rate-limited > error > nil zodat één centrale `SyncStatusBanner` op het Dashboard alle drie de meldingen consistent rendert. F2: `FitnessDataError.rateLimited(retryAfter:)` + `StravaRateLimitParser` extraheert het `Retry-After`-tijdstip (delta-seconds én HTTP-datum, fallback 15 min) en `StravaRateLimitStore` persisteert de cooldown over app-launches heen zodat een retry-storm vlak na launch onmogelijk wordt. F5: `NetworkReachabilityMonitor` (NWPathMonitor-wrapper, singleton) zet de offline-state. `.missingToken` is bewust uitgefilterd — gebruikers zonder Strava-koppeling krijgen geen banner. 24 unit-tests (11 parser + 13 banner-builder) + 4 nieuwe FitnessDataService 429-tests.
  - **⏳ F3 + F4 + F6:** HK per-type permissie, weer-fout non-blocking met retry-marker, captive-portal-detectie
* **⏳ 51.G — Proactieve coach (achtergrond):** status-rij in Settings, notificatie-permissie pre-check, registratie-fout zichtbaar
* **✅ 51.H — App-updates & data-veiligheid:** `MigrationFallbackStore` + Dashboard-`MigrationFallbackBanner` sluit de halve implementatie uit CLAUDE.md §12 (de `vibecoach_migrationFallbackAt`-flag wordt nu daadwerkelijk getoond bij de gebruiker); `AppVersionInfo` rendert marketing-versie + build-nummer onderaan Settings. 11 unit-tests (5 store + 6 version-info). Gemerged via PR #267.

**Volgorde:** start met de quick wins die data-bescherming raken (H + C), dan de coach-reputatie-items (A1, A5), dan sync-zichtbaarheid (F1, F2, F5), dan de overige groepen.

---

### ✅ Epic #52: Workout-analyse aanscherpen (weer + prompt + cadens)

Aanleiding: gebruikersfeedback bij een 90-minuten-hardloop op 24 mei 2026. Drie afwijkingen op het verwachte gedrag van de workout-detail-coach:
1. **Weer-snapshot mismatcht werkelijkheid.** HK-metadata logt één temperatuur bij rit-start (15°C om 9:43); tijdens de rit liep het op naar ~22°C. De Coach kreeg alleen die 15°C te zien en kon de hitte niet meewegen.
2. **Prompt eindigt met een vraag.** De analyse op `WorkoutAnalysisView` heeft geen chat-functie, dus elke open vraag aan de gebruiker blijft hangen.
3. **Geen cadens-grafiek voor hardlopen.** Cycling toont cadens via `cyclingCadence`; running heeft géén native HK-identifier en bleef leeg, terwijl Strava-streams cadens al zelf leveren.

**Sub-stories** (één Epic-PR conform multi-story workflow):

* **✅ 52.1 — Hourly weer-aggregaat over workout-venster:** `HistoricalWeatherService.fetchWeatherRange(latitude:longitude:startDate:endDate:)` haalt alle uurlijkse Open-Meteo-waarden binnen `[start, end]` op en aggregeert tot peak + avg voor temperatuur en luchtvochtigheid (pure helper `extractWindowAggregates` — 4 unit-tests). `WorkoutInsightService.InsightContext` krijgt 4 nieuwe range-velden; `buildPrompt` toont een `[WEER TIJDENS WORKOUT — range]`-blok bij aanwezigheid, anders het bestaande snapshot-blok. System-instruction-paragraaf bijgewerkt: piek-temperatuur is de ondergrens voor hitte-stress-evaluatie. Schema V3 → V4 (lightweight migration) voegt `startLatitude` + `startLongitude` toe aan `ActivityRecord`; `enrichRecord` persisteert die bij elke Strava-ingest zodat de Coach-call achteraf de range kan ophalen zonder de Strava-API opnieuw te bevragen. SchemaV3 krijgt zijn eigen `ActivityRecord`-snapshot (mei-2026-incident-vangnet conform CLAUDE.md §2.1). 4 unit-tests V3→V4-migratie (FitnessGoal + UserPreference overleven, coords schrijfbaar na migratie).
* **✅ 52.2 — Coach-prompt strikter: geen vragen meer:** system-instruction op meerdere plaatsen aangepast — "Eindig met een open vraag" en "stel een kalibratie-vraag" vervangen door observatie-statements. Nieuwe top-level regel: "Deze analyse verschijnt op een detail-view zonder chat-functie. Stel **nooit** een vraag aan de gebruiker." Afsluiter onderaan: "Eindig nooit met een vraagteken." Geen code-safety-net (alleen prompt-instructie) — als Gemini bij hoge uitzondering tóch een vraag genereert, valt dat op tijdens on-device validatie.
* **✅ 52.3 — Running cadens-grafiek + Coach-context:** `WorkoutSampleService.fetchRunningStepCadence` aggregeert HK `stepCount` via `HKStatisticsCollectionQuery` over 5s-buckets en rekent om naar steps-per-minute. Strava cadence-stream blijft de fallback (al ondersteund door bestaande ingest). Nieuwe `cadenceChart` in `WorkoutAnalysisView` voor running-workouts (LineMark + scrubber, geen normatieve zone-bands). `WorkoutInsightService.InsightContext` krijgt `averageCadenceSPM` + `peakCadenceSPM`; system-instruction-paragraaf voor cadens met drempels (160 / 180 spm, piek-vs-gem > 20 spm) en de regel dat cadens alleen wordt aangeroerd bij een gerelateerd pattern. Cache-fingerprint uitgebreid met cadens zodat nieuwe samples een fresh analyse triggeren. De scrubber-card ("details bij tijdstip") toont de spm op de gescrubde positie.

**Post-merge fixes (na on-device validatie):**
* **One-shot re-ingest bij ingest-revisie-bump:** `DeepSyncService` houdt een processed-UUID-set bij om dubbel-fetchen te voorkomen. Bestaande HK-running-workouts zaten daarin → de nieuwe stepCount-cadens werd nooit voor ze opgehaald. `currentIngestRevision = 2` triggert bij launch een eenmalige re-ingest (processed-set wissen) zodat álle workouts in het 30-daagse venster opnieuw de rijkere sample-set krijgen.
* **Cross-source cadens (Strava-dedup-winnaar):** een Apple Watch-run komt vaak óók als Strava-activiteit binnen; bij dedup wint het Strava-record (`device_watts` → +500 in `ActivityDeduplicator.score`) en de view vraagt samples op onder de Strava-UUID, terwijl de Watch-`stepCount` onder de HK-UUID leeft. `WorkoutSampleService.fetchStepCadence(start:end:)` losgemaakt van `HKWorkout` zodat een tijd-window-query (HealthKit dedupliceert stepCount zelf over bronnen) de cadens alsnog vindt. `WorkoutAnalysisView` valt hierop terug (`loadCadenceFallbackIfNeeded`) wanneer de opgeslagen samples geen cadens bevatten; grafiek + Coach-prompt + scrubber gebruiken een unified `cadencePoints`-bron.

**Effort gerealiseerd:** ~750 LOC over `Models/`, `Services/`, `Views/` + 13 nieuwe unit-tests (7 weer-range + 4 schema-migratie + 2 ingest-revisie).

**Status:** ✅ — gemerged op `main` via PR #275 (squash). On-device gevalideerd: weer-range, geen-vragen-prompt en cadens-grafiek (incl. cross-source HK-fallback) werken.

---

### ✅ Epic #53: Multi-Provider BYOK — OpenAI, Claude & Mistral

Aanleiding: sinds Epic #20 (Sprint 20.1) bestaat de `AIProvider`-enum (`gemini` / `openAI` / `anthropic`) al in de UI, maar `AIProvider.isSupported` retourneert **alleen voor `.gemini` true** — de andere keuzes zijn dode opties. De volledige inferentie-laag is Gemini-only: de "abstractie" `GenerativeModelProtocol` lekt het Google-SDK-type `ModelContent.Part`, en `UserAPIKeyStore` bewaart precies één sleutel onder `VibeCoach_UserAIKey`. Doel van deze Epic: de drie resterende providers (OpenAI, Anthropic Claude, **Mistral** — nieuw toe te voegen aan de enum) volwaardig laten werken als BYOK-keuze, inclusief onboarding, Settings, model-selectie, validatie en testsuite. De gebruiker brengt zijn eigen sleutel; calls gaan direct van device naar de provider (geen proxy in het inferentie-pad, conform de bestaande BYOK-filosofie — zie [ARCHITECTURE.md §3](ARCHITECTURE.md)).

**Architectuur-uitgangspunten (vóór implementatie te bevestigen):**

1. **Provider-neutrale abstractie i.p.v. SDK-lek.** `GenerativeModelProtocol.generateContent(_ parts: [ModelContent.Part])` hangt nu rechtstreeks aan `GoogleGenerativeAI`. Dat type moet vervangen worden door een eigen value-type (bv. `AIPromptPart` met `.text` / `.imageData`-cases) zodat de protocol-laag SDK-vrij wordt. Raakt: `RealGenerativeModel`, `ChatViewModel.buildGenerativeModel` (bouwt nu `[ModelContent.Part]`), `WorkoutInsightService`, `MockGenerativeModel`, `UITestMockGenerativeModel`.
2. **Lichte REST-clients i.p.v. drie extra SDK's.** De app heeft maar één call-patroon nodig: single-shot prompt → tekst/JSON-respons. OpenAI (`/v1/chat/completions`), Anthropic (`/v1/messages`) en Mistral (`/v1/chat/completions`) zijn met een dunne `URLSession`-client te bedienen. Dat houdt de SPM-footprint klein (alleen `GoogleGenerativeAI` blijft een dep) en vermijdt SDK-versie-drift. Beslissing per provider documenteren in `ARCHITECTURE.md`.
3. **Per-provider verschillen die de adapter moet afvangen:**
   - **System-instructie:** Gemini `systemInstruction`, OpenAI/Mistral `role: "system"`-message, Anthropic top-level `system`-parameter.
   - **JSON-output:** Gemini `responseMIMEType: "application/json"`, OpenAI/Mistral `response_format: {type: "json_object"}`, Anthropic heeft geen native JSON-mode → prompt-gedreven + eventueel assistant-prefill. De bestaande `extractCleanJSON`-helper blijft het vangnet.
   - **Auth- & rate-limit-fouten:** elke provider heeft eigen HTTP-codes/foutbodies. Mappen naar een uniform `AIProviderError` zodat de bestaande 503/429-waterfall (primair → fallback) en de auth-foutdetectie in `ChatViewModel` provider-agnostisch blijven.
4. **Per-provider sleutelopslag.** `UserAPIKeyStore` bewaart één sleutel; bij providerwissel zou de andere sleutel verloren gaan. Migreren naar keyed opslag (`VibeCoach_UserAIKey_<provider>`) met eenmalige migratie van de bestaande sleutel naar de `gemini`-slot (idempotent, conform de bestaande `migrateFromUserDefaultsIfNeeded`-aanpak).

**Sub-stories:**

* **✅ 53.1 — Provider-neutrale abstractielaag + factory:** `GenerativeModelProtocol` losgeweekt van `GoogleGenerativeAI` — nieuw SDK-vrij `AIPromptPart`-type (`.text` / `.imageData`) + `AIProviderError`-enum + `RealAIProviderClient`-marker in `GenerativeModelProtocol.swift`. Nieuwe `AIModelFactory.makeModel(provider:modelName:systemInstruction:jsonMode:timeout:apiKey:session:)` routeert per `AIProvider` naar de juiste client; `RealGenerativeModel` (Gemini-adapter) verhuisd naar de factory. `ChatViewModel.buildGenerativeModel`, `WorkoutInsightService.makeModel` en `AddGoalView.fetchAITargetTRIMP` routeren nu via de factory. Overload-detectie geüniformeerd via `AIProviderError.isOverload(_:)` (herkent Gemini `internalError` én eigen `.overloaded`).
* **✅ 53.2 — REST-clients voor OpenAI, Claude & Mistral:** `OpenAICompatibleModelClient` (bedient OpenAI + Mistral via `/v1/chat/completions` met `Authorization: Bearer`; één gedeelde client i.p.v. twee near-identieke types — DRY) en `AnthropicModelClient` (`/v1/messages`, `x-api-key` + `anthropic-version`, JSON via assistant-prefill `{`). System-instructie-plaatsing en JSON-mode per provider, base64-vision-parts, fout-mapping naar `AIProviderError` via `AIProviderHTTP.validate` (429/503/529 → `.overloaded`, 401/403 → `.authenticationFailed`). Transport-fouten bubbelen als `URLError` door naar de bestaande mapper. Timeout via `URLRequest.timeoutInterval`. 16 unit-tests in `AIModelClientTests` (URLProtocol-mock, geen live calls). **Mistral-enum-case** (`AIProvider.mistral`) vooruitgehaald uit 53.3 zodat de factory-switch compleet is; key-opslag-per-provider + UI blijven in 53.3/53.6.
* **✅ 53.3 — Per-provider sleutelopslag + `isSupported`:** `UserAPIKeyStore` heeft nu per-provider slots (`serviceName(for:)` → `VibeCoach_UserAIKey_<raw>`) met `read/write/delete(for:)` + DI-varianten. Eenmalige `migrateToPerProviderKeysIfNeeded` verplaatst de legacy single-key naar de Gemini-slot (idempotent, draait in `AIFitnessCoachApp.init()` na de UserDefaults→Keychain-migratie). `AIProvider.isSupported` → `true` voor alle vier; nieuwe `AIProvider.current(in:)` + `appStorageKey` als centrale provider-bron. ChatViewModel/WorkoutInsightService/AddGoalView/Settings lezen/schrijven de slot van de **actieve** provider; Settings herlaadt de sleutel + reset de test-status bij providerwissel. UI-test-reset wist alle provider-slots.
* **✅ 53.4 — Model-selectie per provider:** `AIModelCatalog.builtIn(for:)` levert een gecureerde statische catalogus per provider (Gemini = de bestaande Worker-catalogus). Defaults: OpenAI `gpt-4.1` + `gpt-4.1-mini`, Claude `claude-sonnet-4-6` + `claude-haiku-4-5`, Mistral `mistral-large-latest` + `mistral-small-latest`. `AIModelAppStorageKey` is provider-aware (`primaryKey(for:)`/`resolvedPrimary(for:)` etc.); Gemini behoudt de legacy Epic #35-keys (backward-compat). ChatViewModel resolvet primair/fallback/snapshot/banner consistent via `currentProvider` (voorkomt rebuild-loop). De provider-specifieke model-*pickers* in Settings blijven 53.6; tot dan gebruiken niet-Gemini providers hun default-model.
* **✅ 53.5 — Multi-provider sleutel-validatie:** `APIKeyValidator.validate(_:provider:)` pingt het goedkoopste model per provider via de factory; `classify(_:)` generaliseert naar `AIProviderError` (auth → invalidKey, overloaded → rateLimited). `validateGeminiKey` blijft als back-compat-alias. De "Test sleutel"-knop in Settings werkt nu voor elke provider. `AIProviderHTTP.validate` neemt de (ingekorte) provider-foutbody mee in `AIProviderError.http(status:message:)` zodat een 4xx de échte reden toont (bv. een gedeprecieerd model) i.p.v. een kale statuscode.
* **✅ 53.6 — Settings-UI uitbreiding:** `AIProviderSettingsView` toont een provider-picker met alle vier opties; per geselecteerde provider de juiste `keyPlaceholder`, `getKeyURL`-link, sleutelveld (uit de per-provider Keychain-slot) en model-picker. Gemini = live Worker-catalogus (Epic #35); OpenAI/Claude/Mistral = statische `AIModelCatalog.builtIn(for:)` met `@State`-gebonden pickers (`PrimaryProviderModelPicker`/`FallbackProviderModelPicker`) die provider-gescheiden naar de `AIModelAppStorageKey`-keys persisteren. De "Test sleutel"-feedback en `aiCoachConnectionSubtitle` (Epic #43) tonen de actieve provider via `AIProvider.shortName`.
* **✅ 53.7 — Onboarding-flow:** stap "Jouw AI" (`OnboardingView` + `AIProviderPrivacyContent`) toont nu alle vier providers (segmented, via `shortName`) + een `getKeyURL`-link voor de gekozen provider. Sleutel-invoer blijft uitgesteld naar Settings; "Sla over, doe later" + de `NoAPIKeyView`-lege-staat werken ongewijzigd voor elke provider.
* **✅ 53.8 — Call-site-sanering:** `AddGoalView.fetchAITargetTRIMP()` gerefactord naar de factory (volgt nu de Epic #35-modelkeuze i.p.v. hardcoded `gemini-flash-latest`), `print`-debug-aids verwijderd. `import GoogleGenerativeAI` verwijderd uit `ChatViewModel`, `WorkoutInsightService`, `AddGoalView` en `UITestMockEnvironment` + de unit-test-`MockGenerativeModel`. Na deze sprint importeert alleen nog de `AIModelFactory` (Gemini-adapter) en `APIKeyValidator` (volgt in 53.5) de SDK. `ChatErrorMessageMapper` + `WorkoutInsightService.mapError` herkennen nu ook `AIProviderError`.
* **✅ 53.9 — Testsuite + docs:** mocks aangepast aan de SDK-vrije signatuur (sprint A); per-client `URLProtocol`-tests, per-provider validator-tests, keyed key-store-migratietest (sprint A+B); `AIProvider.shortName`-test + een providerwissel-UI-test (`testSwitchingToMistral_ShowsProviderModelPicker`) in `AIModelPickerUITests`. `ARCHITECTURE.md §3` beschrijft de hele abstractie + per-provider-verschillen; `architecture.json`/`.html` gesynct (`AIModelFactory`-module, `docRevision` gebumpt) conform [CLAUDE.md §7](../CLAUDE.md#architectuur-visualisatie-afgeleide-artefacten).

**Open punten / risico's:**

- **Anthropic JSON-betrouwbaarheid:** zonder native JSON-mode is prompt-gedreven JSON kwetsbaarder. De `SuggestedTrainingPlan`-decode + `extractCleanJSON` moeten dit afvangen; mogelijk assistant-prefill (`{`) inzetten. On-device valideren met een echt plan-genererend gesprek.
- **Kosten/latency-profiel verschilt per provider** — de 45s-timeout en de 503/429-waterfall zijn op Gemini afgestemd; per provider verifiëren dat fallback-gedrag zinvol is.
- **System-instructie is ~274 regels NL** (zie Epic #37.2). Die prompt is op Gemini getuned; toon-verschillen tussen providers manifesteren zich pas in productie (subjectief). On-device A/B per provider aanbevolen vóór "supported" claimen.
- **Scope-grens:** geen streaming, geen multimodale input buiten de bestaande tekst+image-parts, geen provider-specifieke safety-settings (alle providers op defaults, net als nu bij Gemini).

**Effort-schatting:** ~3 PR's. (A) 53.1 + 53.2 + 53.8 — abstractie + clients + call-site-sanering (kern, ~grootste post). (B) 53.3 + 53.4 + 53.5 — sleutelopslag + model-catalogus + validatie. (C) 53.6 + 53.7 + 53.9 — UI + onboarding + tests + docs. Grof ~30–40u afhankelijk van hoeveel per-provider-tuning de prompt vergt.

**Status:** ✅ — afgerond in drie sprints (PR #276 sprint A, PR #277 sprint B, sprint C op `feature/epic-53-byok-ui-onboarding`). Gemini/OpenAI/Claude/Mistral zijn alle vier volwaardige BYOK-keuzes: per-provider Keychain-slots, per-provider model-pickers (Gemini live Worker-catalogus, overige statisch), per-provider validatie en een provider-aware onboarding-stap. On-device gevalideerd door de gebruiker: Mistral-coach werkt end-to-end, Claude-sleutel wordt geaccepteerd (alleen credit-saldo ontbrak), foutmeldingen tonen de echte provider-reden. Bestaande Gemini-gebruikers ongewijzigd (legacy-key gemigreerd, modelkeuze + AppStorage-keys behouden). 912 unit-tests + UI-tests groen.

---

### ✅ Epic #54: Dynamische model-catalogus per provider

Aanleiding: na Epic #53 koos de model-picker per niet-Gemini provider uit een **statische** `AIModelCatalog.builtIn(for:)`-lijst. Die veroudert snel — een gebruiker zag in zijn OpenAI-account al gpt-5.4 / gpt-5.5-pro terwijl de app `gpt-4.1` als nieuwste toonde. Doel: de modellijst per provider live ophalen, net zoals Gemini dat via de Cloudflare Worker doet.

**Aanpak:** elke provider heeft een `/v1/models`-endpoint dat we **direct vanaf het toestel met de BYOK-sleutel** aanroepen — de sleutel verlaat het toestel niet via onze servers (net als de chat-calls), dus géén privacy-regressie en de lijst is gebruiker-specifiek. Gemini blijft bewust op de Worker (globale, gevalideerde lijst met onze eigen key); voor OpenAI/Anthropic/Mistral zou de Worker-route de user-key moeten doorgeven, wat we niet willen.

* **✅ 54.1 — `ProviderModelListService`:** haalt `/v1/models` op per provider (OpenAI `Authorization: Bearer`, Anthropic `x-api-key` + `anthropic-version`, Mistral `Bearer`), parseert de gedeelde `{ data: [...] }`-vorm en **filtert naar chat-modellen**: Anthropic = alles (alleen `claude-*`), Mistral = `capabilities.completion_chat`, OpenAI = heuristiek op id (`gpt-`/`chatgpt-`/`o1`/`o3`/`o4`, met uitsluiting van embedding/audio/realtime/transcribe/tts/image/whisper/etc.). Aflopend gesorteerd (nieuwste bovenaan). Valt via de caller terug op `AIModelCatalog.builtIn(for:)` bij fout/lege key. Leeft in `AIModelFactory.swift` (client-subsysteem). 7 unit-tests (URLProtocol-mock, geen live calls).
* **✅ 54.2 — Settings-wiring:** `AIProviderSettingsView` toont de live lijst voor niet-Gemini providers — begint met de statische lijst (picker nooit leeg), vervangt die zodra de fetch slaagt, en reset een opgeslagen keuze die niet meer in de live lijst staat (gedeprecieerd model). Ververst op `onAppear`, bij providerwissel en na een geslaagde sleutel-test. Footer toont de laad-/bron-status. Gemini behoudt de Worker-catalogus.

**Open punten:** geen persistente cache (fetch per Settings-open, zoals Gemini's Worker-route); de OpenAI-chat-filter is heuristisch (een toekomstig niet-chat `gpt-*`-model zou kunnen doorglippen — dan vangt de coach-call-foutbody het op). Eventuele follow-up: caching met TTL + een handmatige "ververs modellen"-knop.

**Status:** ✅ — on-device gevalideerd: alle vier providers laden hun live modellijst zodra een sleutel is ingevoerd. Eén UX-verfijning tijdens validatie: zonder ingevoerde sleutel sloeg de fetch stil over (geen fout → leek stuk); footer vraagt nu expliciet om de sleutel in te voeren + te testen, en toont bij een echte fetch-fout de reden (bv. 401/403 als de key geen *Models*-leesrecht heeft). 919 unit-tests groen. PR #279.

---

### ⏳ Epic-backlog: Mentale benefit van workouts

Idee voor een toekomstige Epic — nog niet uitgewerkt. Gedachte: niet alleen fysieke metrics tonen (TRIMP, HR, recovery), maar ook iets over mood/energie/stress-impact zodat de coach kan zeggen "je voelt je hier de rest van de dag goed door" of "deze sessie helpt je stress af te bouwen". Open punten: welke signalen (HRV-respons na rit, post-RPE-mood, slaap-respons in nacht erna), welke UI (extra tegel onder Vibe Score? Veld op WorkoutAnalysisView?), hoe de coach dit framet, en hoe we het onderscheiden van pure fysieke load. Pickup-trigger: gebruiker wil meer expliciete "waarom train ik dit"-context bij workouts.
