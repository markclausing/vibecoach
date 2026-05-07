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

### ⏳ Epic #37: Internationalisatie & Engelse Codebasis (speculatief — nog niet besloten)

Twee samenhangende initiatieven die we mogelijk ooit oppakken: de app meertalig maken (NL + EN als startpunt) én de Nederlandstalige codebasis-comments naar Engels migreren. Deze entry dient als concrete scope-analyse zodat een eventuele go/no-go beslissing op feiten kan worden genomen, niet op gut-feel.

**Status:** Geen commitment. Deze epic blijft op ⏳ totdat er een concreet bedrijfsbelang is (App Store launch buiten NL/BE, open-source bijdragers buiten NL).

#### 37.1 — Multi-language UI (i18n)

| Categorie | Inventaris | Effort |
|---|---|---|
| SwiftUI string-literals (`Text` / `Label` / `Button` / `.navigationTitle`) | 237 | 16–20u extractie + 8–12u catalogus |
| Notificatie-tekst (`ProactiveNotificationService`) | 9 strings | 2–3u |
| `Locale(identifier: "nl_NL")` hardcoded | 19 plekken | 4–6u parameteriseren |
| Localization-infra | 0 (geen `Localizable.xcstrings`) | nul-startsituatie |

**Subtotaal i18n-UI:** ~30–40u (~1 sprint).

#### 37.2 — Multi-language AI-prompt (kritiek pad)

De Gemini system instruction in `ChatViewModel.swift` (regels 538–639) is **89 regels Nederlandse instructie** die bovendien expliciet aan het model vraagt Nederlands terug te geven. Daarnaast bouwen 12 cache-functies (`cacheVibeScore`, `cachePeriodizationStatus`, etc.) **185 regels dynamische Nederlandse context** op (regels 704–888), die in elke prompt geïnjecteerd worden.

JSON-sleutels in de respons zijn al Engels (`motivation`, `workouts`, `dateOrDay`, etc.) — alleen de prose-velden (`motivation`, `description`, `reasoning`) zijn Nederlands. Dat is een geluk: de parser hoeft niet aangepast.

**Aanpak:** systeem-instructie + context-blokken templaten op `Locale.current.languageCode`; lookup-dict per taal i.p.v. inline string-literals. Ook de AI-rol-instructie (`Reageer in het Nederlands…` → `…in the user's language`) moet locale-aware worden.

**Subtotaal AI-prompt-refactor:** 20–24u.

#### 37.3 — NL-afhankelijke detectielogica

Twee plekken waar Nederlandse keywords harde productie-logica aansturen — kunnen niet zomaar vertaald worden:

- **`BodyArea.injuryKeywords`** (`FitnessGoal.swift:18-25`): 13 sleutelwoorden (`kuit`, `scheen`, `rug`, `knie`, `enkel`, …) detecteren blessures in user-input. Voor EN moet dit een per-taal keyword-set worden.
- **`BodyArea.severityLabel`** (`FitnessGoal.swift:39-47`): pijn-niveau labels (`Geen pijn`, `Licht`, `Matig`, `Zwaar`, `Ernstig`).

Positief: `SuggestedWorkout.resolvedDate` parseert dagnamen al **bilingual NL+EN** — dat patroon (per-taal lookup-table) kan voor de andere uitgebreid worden.

**Subtotaal:** 4–6u.

#### 37.4 — Comment-migratie naar Engels

| Metric | Aantal |
|---|---|
| Totaal comment-regels (`grep -rE "^\s*//"`) | 3.168 |
| Geschat % Nederlands (steekproef 20 files) | ~85% |
| Nederlandse comment-regels | ~2.700 |
| `// MARK:`-kopjes in NL (Sprint/Epic refs) | ~24 |
| Variabelen al Engels? | **Ja** (Swift-conventie strikt gevolgd, sample 50/50 Engels) |

**Risico's:** grote git-blame pollution (~2.700 regel-diff in één PR), mogelijke merge-conflicts met parallelle PR's, devs die op NL-keywords zoeken (`grep "Periodisering"`) moeten omgewenstellen.

**Geen runtime-impact** — comments hebben geen functie; review-only risico.

**Subtotaal:** 27–35u (~1 sprint), kan parallel met i18n.

#### 37.5 — Locale-switch in Settings

Toggle in `SettingsView` om expliciete taalkeuze te overrulen (default: device-locale). Vraagt app-restart of state-reload via `@Environment(\.locale)` propagatie.

**Subtotaal:** 6–8u.

#### Effort-overzicht

| Fasen | Uren | Sprints |
|---|---|---|
| 37.1 i18n-UI + 37.5 settings-toggle | 36–48u | 1 |
| 37.2 AI-prompt-refactor (kritiek pad) | 20–24u | 0.5 |
| 37.3 detectie-logica | 4–6u | 0.1 |
| 37.4 comment-migratie (parallel mogelijk) | 27–35u | 0.7 |
| QA, regressie-tests, beide talen | 12–16u | 0.4 |
| **Totaal** | **~100–130u** | **~3 sprints** |

#### Aanbevolen aanpak (als ooit gestart)

1. **Optie minimal:** alleen 37.1 + 37.5 + 37.3 → ~50u (1.5 sprint). UI is meertalig, AI blijft Nederlands. Werkt voor App Store-listing maar niet voor non-NL gebruikers.
2. **Optie compleet:** alle sub-tasks → ~100–130u. Echte meertalige app inclusief AI-coach in de gekozen taal.

#### Blokkers en risico's

- **AI prompt-complexiteit:** de 274 regels Nederlandse instructie + dynamische context zijn de zwaarste post. Wijzigingen aan de system instruction hebben coach-gedragsimpact die zich pas in productie manifesteert (subjectieve toon).
- **Test-coverage:** alle UI-tests gebruiken hardcoded NL assertions (`"Goedemorgen…"`, `"Doelen"`-titels). Per taal moet een test-variant of een geforceerde locale-fixture komen.
- **Backwards-compat voor bestaande NL-gebruikers:** default moet `Locale.current` blijven; geen forced switch.
- **Scope-creep:** `CLAUDE.md`, `README.md` en `docs/` blijven Nederlands tot een eventuele v2.0 — anders eindeloze documentatie-vertaling. Comment-migratie (37.4) raakt alleen `.swift`-bestanden.

#### Lage-hangend-fruit als we tóch incrementeel willen beginnen

- **37.5 (Locale-switch UI)** kan losstaand als voorbereidende refactor — geeft toekomstige PR's ergens om naar te toggle.
- **37.4 (Comment-migratie)** is volledig ontkoppeld van runtime — kan in stilstaande periodes geleidelijk worden opgeruimd, één service tegelijk.

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

### ⏳ Epic #46: GitHub Actions DAG-Visualisatie & Pipeline-Uitbreiding

Aanleiding: het GitHub Actions Summary-tabblad rendert een visuele DAG van jobs zodra een workflow uit meerdere jobs bestaat met `needs:`-relaties (zie referentie-screenshot van een full-stack web-app: Build → Tests → Deploy → Smoke). Op dit moment heeft VibeCoach één monolitische `Build & Test`-job in `ios-tests.yml` plus een losse `CodeQL`-workflow — geen visualisatie omdat er niets te chainen valt. Doel van deze Epic: de iOS-pijplijn opsplitsen in losgekoppelde jobs voor visueel inzicht en parallellisatie, zonder de complexiteit van signing/secrets binnen te halen. Backlog-stories houden zwaardere uitbreidingen (TestFlight, snapshot-tests, dependency-scan) zichtbaar voor het moment dat er concrete pijn ontstaat.

**Scope-keuze:** het screenshot toont een web-app pipeline met deploy-naar-acceptance/productie en Playwright. Dat patroon is niet 1-op-1 toepasbaar — App Store-distributie via TestFlight vraagt een Apple Developer-account, App Store Connect API-key en signing-certs in GitHub Secrets. Die staan in de backlog (46.B1), niet in de hoofd-scope.

**Sub-stories (laagdrempelig — geen extra secrets):**

* **⏳ 46.1 — Splits `ios-tests.yml` in `unit-tests` + `ui-tests` jobs:** Eén `unit-tests`-job die `xcodebuild test` draait met `-only-testing:AIFitnessCoachTests`, plus een `ui-tests`-job met `needs: unit-tests` en `-only-testing:AIFitnessCoachUITests`. Beide draaien op `macos-latest` met dezelfde Xcode-select + `Secrets-template.swift`-copy. Tradeoff: 2× macOS-runner-tijd per push (UI-tests booten een aparte simulator), maar UI-falen kan geen unit-test-feedback meer vertragen. **Open ontwerpkeuze:** een `Setup`-job die simulator-bootstraps en build-artifacts deelt via `actions/upload-artifact` zou dubbele build voorkomen, maar voegt ~30s overhead toe en complexere caching — pas optimaliseren als de runner-tijd echt knelt.
* **⏳ 46.2 — Parallele `lint`-job (SwiftLint):** Nieuwe job `lint` zonder `needs`-relatie (start tegelijk met `unit-tests`). Gebruikt `realm/SwiftLint`-action of `brew install swiftlint` met een minimale `.swiftlint.yml` die alleen high-signal regels aanzet (`force_unwrapping`, `force_cast`, `todo`-warnings). Voorwaarde: codebase moet eerst clean zijn — een eerste run zal naar verwachting 50–200 violations tonen die als losse PR's of als bewuste opt-in (`disabled_rules`) afgehandeld moeten worden. **Risico:** SwiftLint-adoptie zonder code-cleanup blokkeert elke PR; eerst `disabled_rules` op alles, dan rule-by-rule aanzetten.
* **⏳ 46.3 — `coverage-report`-job als PR-artifact:** Hangt aan `needs: unit-tests`. Draait `xcrun xccov view --report --json` over de `.xcresult`-bundle uit story 46.1, formatteert naar markdown met per-target coverage, en upload als `actions/upload-artifact`. Optioneel: een PR-comment-action die het percentage in de PR-discussie post (gebruikt `GITHUB_TOKEN`, geen extra secret). Vervangt het handmatige `xcodebuild -enableCodeCoverage YES`-tellen dat nu de README-status bijhoudt (51% — Epic #36).

**Backlog (zichtbaar houden, geen toezegging):**

* **⏳ 46.B1 — TestFlight-deploy job op merge naar main:** `deploy-testflight`-job met `needs: [unit-tests, ui-tests]` en `if: github.ref == 'refs/heads/main'`. Vereist eenmalige setup: Apple Developer-account, App Store Connect API-key (`.p8`), signing-cert + provisioning-profile in GitHub Secrets, en `fastlane match` of `xcodebuild -exportArchive` met `ExportOptions.plist`. Effort: ~4–6u eenmalig voor cert-setup + workflow-syntax, daarna onderhouds-vrij. Pickup-trigger: gebruiker wil App Store Connect TestFlight-flow automatiseren i.p.v. handmatig archive uploaden.
* **⏳ 46.B2 — Snapshot-tests via `swift-snapshot-testing`:** PointFree's library voor view-snapshots (PNG-diff op kritieke schermen: Dashboard, Goals, Chat, Settings). Job `snapshot-tests` met `needs: unit-tests`. Eerste run genereert reference-images die in repo gecheckt worden; daarna faalt CI op visuele regressies. Effort: ~6–8u (library integreren + 5–10 reference snapshots schrijven). Pickup-trigger: een UI-regressie die door bestaande XCUITests niet werd gevangen.
* **⏳ 46.B3 — Dependency vulnerability scan:** GitHub `dependency-review-action` op PR's die `Package.swift`/`Package.resolved` raken. Vergelijkt nieuwe transitive deps met de GitHub Advisory Database. Effort: ~30 min. Pickup-trigger: Swift Package Manager wordt actief gebruikt voor third-party deps (op dit moment minimaal — alleen bestaande Anthropic/Strava-koppelingen via REST).
* **⏳ 46.B4 — Performance regression checks:** Build-tijd-tracking (`xcodebuild`-output parsen) en/of een lichte `XCTMetric`-baseline (launch-tijd, dashboard-render) als eigen job met historisch artifact-vergelijk. Effort: ~4u. Pickup-trigger: gebruiker meldt subjectieve traagheid en we willen objectieve baselines.
* **⏳ 46.B5 — Concurrency-strict-build als matrix-cel:** Voortbouwend op Epic #39 story 39.3 — een matrix-cel die met `SWIFT_STRICT_CONCURRENCY=complete` bouwt zodat nieuwe Sendable-warnings als CI-fail naar boven komen, zonder de hoofd-build te breken. Effort: ~1u zodra 39.3 zelf gedaan is.
* **⏳ 46.B6 — Semver-versioning via `release-please` + git-tag-gebaseerde `MARKETING_VERSION`:** Release-mechaniek, onafhankelijk van 46.B1 bruikbaar (tag + GitHub Release hebben los waarde als release-historie). Drie sub-stappen: (1) `googleapis/release-please-action` workflow op main; bot opent een Release PR die accumuleert tot jij 'm mergt — bij merge wordt automatisch de git tag (`v1.2.3`) + GitHub Release met changelog aangemaakt. Patch/minor/major afgeleid uit Conventional Commits-prefixen (`fix:` / `feat:` / `feat!:`). (2) Run Script Build Phase die `CFBundleShortVersionString` bij build-tijd uit `git describe --tags --abbrev=0` zet, parallel aan de bestaande `CFBundleVersion = git rev-list --count HEAD`-aanpak. Eén source of truth (de tag), geen `MARKETING_VERSION`-mutatie in `project.pbxproj` nodig — dat bestand houdt z'n `skip-worktree`-flag (CLAUDE.md §9). (3) Conventional Commits formaliseren in CLAUDE.md §8 als harde regel — wordt al gevolgd in de praktijk, maar release-please vertrouwt op consistentie. Effort: ~2-3u eenmalig. Pickup-trigger: eerste echte release (TestFlight friendly-users of App Store), of eerder als je release-historie expliciet wil maken voordat de eerste release uitgaat.

**Effort hoofd-scope (46.1 + 46.2 + 46.3):** ~3–4u in één PR. Voornaamste risico is SwiftLint (46.2) — kan een aparte voorbereidende PR vragen om de codebase eerst clean te maken; in dat geval splitst 46.2 zich in een "infra-PR" + een "rule-by-rule cleanup-PR".

**Status:** ⏳ — voorgesteld, nog niet gestart. Begin-volgorde wanneer opgepakt: 46.1 (mechanische split, direct visueel resultaat in Actions-tab) → 46.3 (coverage-artifact piggybackt op 46.1's `.xcresult`) → 46.2 (alleen als we de SwiftLint-cleanup ook willen doen, anders skippen).
