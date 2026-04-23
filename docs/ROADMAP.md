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

### ⏳ Epic #32: Deep-Dive Fysiologische Analyse

Van gemiddelden naar granulaire fysiologische patronen. De coach leest het volledige verhaal uit de ruwe tijdreeksdata.

* **Story 32.1 — Time-Series Data Pipeline:** Breid de sync uit om gedetailleerde samples (per 5–10 seconden) van hartslag, vermogen, snelheid en cadans op te halen. Granulaire opslag als aparte `@Model` voor workout-samples.
* **Story 32.2 — Annotated Charts UI:** Interactieve grafiek met meerdere datastromen over elkaar. De coach kan specifieke tijdstempels 'pinnen' met annotaties.
* **Story 32.3 — AI Pattern Recognition:** AI zoekt naar fysiologische fenomenen (decoupling, cadans-verloop, herstelvermogen). Patronen als annotaties én contextuele insights.

---

### ⏳ Epic #33: Geavanceerde Sessie-architectuur

Trainingen zijn sessies met expliciete fysiologische intentie.

* **33.1 — Sessie-Type Taxonomie:** `VO2maxSession`, `TempoRun`, `LongRun`, `Intervals`, `SocialRideRun`, `Recovery`. Type-veilige enums conform CLAUDE.md §2.
* **33.2 — Flexibele Planning (The 'Swap'):** Gebruiker kan een geplande sessie 'swappen'. Coach herberekent de resterende weekbelasting automatisch.
* **33.3 — Sociale Modus:** Specifieke logica voor sociale ritten — minder streng op zones, meer focus op mentaal herstel en Vibe Score.
* **33.4 — Intentie vs. Uitvoering:** Coach vergelijkt gepland sessietype met werkelijkheid en geeft specifieke feedback bij structurele afwijkingen.

---

### ⏳ Epic #35: Dynamische Gemini Model-Selectie in Settings

* **35.1 — GeminiModelCatalog Service:** Bij het openen van Settings → `GET /v1beta/models?key=...`. Filter op `supportedGenerationMethods.contains("generateContent")` en `gemini-*`. 24u TTL-cache in `UserDefaults`.
* **35.2 — Dual-Picker UI:** Twee `Picker`-componenten ("Primair model" / "Fallback model"). Defaults: `gemini-flash-latest` + `gemini-flash-lite-latest`. `@AppStorage`-keys `vibecoach_primaryModel` / `vibecoach_fallbackModel`.
* **35.3 — Validatie & Graceful Degradation:** Bij app-start guard tegen deprecatie. Stille fallback + niet-blokkerende notificatie in Settings.
* **35.4 — Unit Tests:** `GeminiModelCatalogTests` met `MockNetworkSession` voor filtering + 24u-cache-TTL.
