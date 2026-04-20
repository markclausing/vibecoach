# VibeCoach

Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De app combineert Apple HealthKit data, Strava activiteiten en de kracht van de Gemini AI om dynamisch en proactief je trainingsschema's te evalueren en bij te sturen.

---

## 🚀 Huidige Status
**Actief in Ontwikkeling — Epic #31 ⏳**

VibeCoach is een production-ready iOS-app met fysiologisch correcte trainingscoaching, contextuele weersintelligentie (Open-Meteo), slaapfase-analyse, blessure-bewuste planning en een BYOK AI-architectuur (Gemini / OpenAI / Anthropic). Testsuite: 63% code coverage.

---

## 🛠 Installatie & Setup

Om dit project lokaal te draaien, moet je zowel de iOS-app als de bijbehorende Node.js webhook-backend configureren. Volg de onderstaande stappen:

### 1. iOS App (Xcode)
1. Open `AIFitnessCoach.xcodeproj` in Xcode.
2. Kopieer in de projectmap het bestand `Secrets-template.swift` naar `Secrets.swift`.
3. Open `Secrets.swift` en vul je eigen API-sleutels in (zoals je Gemini API Key en Strava API credentials).
4. Selecteer je simulator of fysieke iPhone en druk op Run (Cmd+R).
*(Let op: voor Apple HealthKit functionaliteit is testen op een fysiek toestel aanbevolen).*

### 2. Backend (Node.js)
De backend luistert naar inkomende Strava webhooks om push-notificaties (APNs) te sturen naar de app.
1. Navigeer in je terminal naar de `backend/` map.
2. Voer `npm install` uit om de afhankelijkheden te installeren.
3. Kopieer het bestand `.env.example` naar `.env`.
4. Open de `.env` file en vul daar de benodigde variabelen in (zoals `CLIENT_ID`, `CLIENT_SECRET`, en je zelfbedachte `VERIFY_TOKEN`).
5. Start de server (bijvoorbeeld via `./start.sh` als je ngrok wilt gebruiken voor lokaal testen).

---

## Kernfunctionaliteiten (Roadmap)

### ✅ Fase 1–9: Fundering & Intelligente Coach (Afgerond)

| Fase | Wat er gebouwd is |
|------|-------------------|
| **1–5** | iOS App (SwiftUI) & SwiftData, OAuth2 Strava, Node.js backend met APNs webhooks, deep-linking op `activityId` |
| **6** | Historische sync, context-injectie & proactieve overtraining-waarschuwingen |
| **7** | Apple HealthKit integratie — Banister TRIMP berekening (HRR, Cardiac Drift, Training Load) lokaal op device |
| **8** | Interactieve 7-daagse trainingskalender; Readiness Calculator injecteert cumulatieve TRIMP + actieve doelen in de prompt |
| **9** | Smart Expiring Memory (tijdelijke blessures krijgen een vervaldatum), workout-acties (Overslaan / Alternatief), Performance Baseline (gemiddeld tempo geïnjecteerd in AI-prompts) |
| **10** | Open Source release — secrets verwijderd, documentatie op orde |
| **11** | Coach UX refactor: `TrainingPlanManager` als Single Source of Truth, centrale TabBar Coach-knop |
| **12** | Multi-Goal Burndown Chart (Swift Charts, schuifbaar), TRIMP Explainer-kaart, hybride Forecast-lijn (gepland schema + historische burn rate) |

---

### ✅ Epic 13: Proactieve Coach & Background Sync (Afgerond)

**Dual Engine Architecture** die de app wakker maakt zonder dat de gebruiker iets hoeft te doen:

* **Engine A (Action Trigger):** `HKObserverQuery` + `enableBackgroundDelivery` — iOS wekt de app bij iedere nieuwe HealthKit-workout. De app checkt direct of een doel op rood staat en stuurt een contextuele push-notificatie met deep-link naar de coach.
* **Engine B (Inaction Trigger):** `BGAppRefreshTask` via `BGTaskScheduler` — dagelijkse stille 24-uurs check. Meer dan 2 dagen inactief én een rood doel? Dan volgt een empathische motivatienotificatie.
* **Recovery Mode:** `requestRecoveryPlan()` bouwt automatisch een gedetailleerde prompt (actuele TRIMP/week, wekelijks tekort, weken resterend) en instrueert de AI een concreet 7-daags bijgestuurd schema te produceren. De rode banner verandert na actie 3 dagen in een blauwe "Herstelplan Actief"-bevestiging.
* **Fysiologische Guardrails:** Harde limieten in de AI-prompt — 10–15% progressieregel, Base Building bij >8 weken resterend, max 60 minuten voor binnensessies.

---

### ✅ Epic 14: De Vibe Score — Readiness (Afgerond)

**HealthKit meets AI:** dagelijkse lichaamsbatterij (0–100) die de coach stuurt.

* **Data ophalen:** `heartRateVariabilitySDNN` (HRV) en `sleepAnalysis` (daadwerkelijke slaapuren, exclusief 'inBed') via HealthKit — volledig lokaal, privacy-first.
* **Algoritme:** `ReadinessCalculator` combineert Slaap (50%, lineair 5–8u) + HRV (50%, actueel vs. 7-daagse persoonlijke baseline) tot een score van 0–100.
* **Dashboard UI:** `VibeScoreCardView` (groen ≥80, oranje 50–79, rood <50) bovenaan het dashboard met batterij-icoon, slaap- en HRV-data. Inklapbare `VibeScoreExplainerCard` legt het algoritme uit.
* **Brain-Body Connection:** De Vibe Score wordt gecached in `AppStorage` en geïnjecteerd in *iedere* AI-prompt. Harde systeeminstructie: de AI mag de score nooit weerspreken en past intensiteitsadvies er automatisch op aan (≥80 = vol gas, 50–79 = voorzichtig, <50 = rust afdwingen).

---

### ✅ Epic 16: Dynamische Periodisering & Macrocycli (Afgerond)

**De app denkt in trainingsfasen** — niet langer een lineaire burndown.

* **Fase-detectie:** `TrainingPhase` enum (`.baseBuilding`, `.buildPhase`, `.peakPhase`, `.tapering`) berekent automatisch de correcte fase op basis van weken resterend tot het doel (>12w / 4–12w / 2–4w / <2w). Fase-badge zichtbaar in `GoalRowView`.
* **Wiskundige Multipliers:** De wekelijkse TRIMP-target schaalt mee — ×1.00 (Base), ×1.15 (Build), ×1.30 (Peak), ×0.60 (Taper). Tapering-overload detectie: te hard trainen in de rustfase (>110% van de verlaagde target) triggert een aparte rode waarschuwing.
* **AI Context:** De coach ontvangt per doel een `[PERIODISERING]` blok met fase-specifieke restricties én de concrete wiskundig aangepaste TRIMP-target — zodat adviezen altijd fysiologisch correct zijn voor de huidige fase.

---

### ✅ Epic 18: Subjectieve Feedback — RPE & Mood (Afgerond)

**Hoe zwaar voelde de training?** — onafhankelijk van wat de hartslagmeter zegt.

* **Post-Workout Check-in:** `PostWorkoutCheckinCard` verschijnt bovenaan het dashboard na een echte training (≤48u geleden, ≥15 min, TRIMP ≥15). Bevat een RPE-slider (1–10) en vijf stemming-knoppen (😌 Rustig · 🟢 Goed · 🚀 Sterk · 🤕 Pijn · 🥵 Uitgeput).
* **Noise Filtering:** Woon-werk ritten en korte wandelingetjes worden automatisch overgeslagen. De 'Negeer'-knop slaat `rpe = 0` op als sentinel zodat de kaart verdwijnt zonder de AI-cache te beïnvloeden.
* **Discrepantie-analyse:** De AI ontvangt een `[SUBJECTIEVE FEEDBACK]` blok in iedere prompt. Harde systeeminstructie: laag TRIMP + RPE ≥8 = vroeg waarschuwingssignaal voor overtraining of naderende ziekte.

---

### ✅ Epic 19: Tech Debt, MVVM Refactor & UI Testing (Afgerond)

Uitgebreide opschoning van de codebase. Toevoeging van XCTest Unit- en UI-tests voor de core gebruikersflows en fysiologische rekenmodellen. De testsuite is succesvol afgerond met een Code Coverage van **62%**.

* **Magic Numbers → Constanten:** `WorkoutCheckinConfig` enum centraliseert de RPE check-in drempelwaarden (minimumDurationSeconds, minimumTRIMP, ignoredRPESentinel).
* **Accessibility Identifiers:** Kerncomponenten gemarkeerd (`VibeScoreCard`, `RPECheckinCard`, `RPESlider`, `ChatInputField`, `AddGoalButton`) voor robuuste UI-testbaarheid.
* **UI-testsuite:** 8 XCUITests voor TabBar-volledigheid, Dashboard rendering, navigatie naar Coach/Doelen/Instellingen en de RPE check-in kaart. HealthKit- en notificatie-popups worden gebypassed via `-isRunningUITests` launch argument.
* **Unit Tests (Epic 14 & 16):** `ReadinessCalculatorTests` (8 tests) verifieert grenscases van het Vibe Score algoritme. `TrainingPhaseTests` (11 tests) verifieert fase-detectie, multipliers en fase-gecorrigeerde TRIMP-berekeningen.

### ✅ Epic 26: UI Test Suite Fixes & ProgressService Unit Tests (Afgerond)

Stabilisatie van de volledige testsuite na refactors en uitbreiding van unit test coverage voor core services.

* **UI Test Suite Reparatie:** Timing-animaties en race-condities in XCUITests opgelost. Alle 8 UI-tests draaien nu stabiel en slagen consistent in CI.
* **ProgressService Unit Tests:** `ProgressServiceTests` uitgebreid met tests voor burndown-berekeningen, gap-analyse en edge-cases (lege data, toekomstige doelen). Volledige happy-path dekking voor de core burndown-logica.
* **Coverage groei:** Code coverage gestegen van 54% naar **62%** over de volledige testsuite.

---

### ✅ Epic 20: App Store Ready — Onboarding & Polish (Afgerond)

De transitie van functioneel prototype naar een portfolio-klare, release-waardige app.

* **Sprint 20.1 — BYOK & Multi-Provider:** `AIProvider` enum (Gemini / OpenAI / Anthropic) met `displayName`, `keyPlaceholder` en `getKeyURL`. `AIProviderSettingsView` in Instellingen. `ChatViewModel` en `AddGoalView` gebruiken dynamisch de opgeslagen sleutel via `effectiveAPIKey()` (gebruiker-sleutel → Secrets-fallback). `NoAPIKeyView` lege staat in de Coach-tab als er geen sleutel is geconfigureerd.
* **Sprint 20.2 — Onboarding Flow:** 4-pagina `TabView` carousel (Welkom → Hoe het werkt → Jouw Data/AI → Permissies). Pagina 3 bevat een inline BYOK-invoerkaart met segmented Picker, SecureField en provider-specifieke 'Hoe kom ik aan een sleutel?' links. Pagina 4 vraagt HealthKit en Notificaties netjes via `PermissionCard` componenten — uitsluitend via knoppen, nooit automatisch. `hasSeenOnboarding` AppStorage routing in de App struct: nieuwe gebruikers zien de onboarding, terugkerende gebruikers gaan direct naar het dashboard. Achtergrond-engines starten pas na voltooiing.
* **Sprint 20.3 — Splash Screen & App Icon:** Native splash screen via `UILaunchScreen` in `Info.plist` — donkere achtergrond (`#0D1117`) met gecentreerd neon-groen logo. Gepolijst App-icoon zonder witte rand. Onboarding beveiligd: geen enkele permissie-request buiten de expliciete knoppen.

### ✅ Epic 14b: Blessure-Impact Intelligentie & Vibe Score Stabiliteit (Afgerond)

Contextuele coaching op basis van blessure-belasting en stabiele Vibe Score berekening.

* **Sprint 14b.1 — Injury-Impact Matrix:** `InjuryImpactMatrix` struct vergelijkt de `SportCategory` van de laatste workout met actieve blessure-voorkeuren. Penalty-multiplier (1.0–1.4×) verhoogt de effectieve TRIMP bij risicovolle sportkoppeling (bijv. kuitklachten + hardlopen = 1.4×). Banner toont contextuele blessure-waarschuwing.
* **Sprint 14b.2 — ACWR-Bannerlogica:** Dashboard-banner gebaseerd op Acute:Chronic Workload Ratio (drempelwaarde 1.5×). Drie states: `overreached`, `lowVibeHighLoad`, `behindOnPlan`. Geen overlap meer met weekdoel-logica. `VibeScoreExplainerCard` inklapbaar toegevoegd.
* **Sprint 14b.3 — Chat UX & Retry:** Verbeterde prompt-suggesties, toetsenbord-gedrag in `ChatView`. `Retry`-knop bij tijdelijke AI-fouten (netwerk/rate-limit).
* **Sprint 14b.4 — Vibe Score Auto-Berekening:** `DashboardView` berekent de Vibe Score automatisch bij `onAppear` als er geen record voor vandaag is. 5-seconden time-out via `withTaskGroup` race-conditie. `defer { isLoading = false }` garandeert reset ook bij fouten. HRV-queryvenster vergroot naar 48u (fallback als Watch gisteravond niet gedragen). Debug print-statements in alle HealthKit-queryfuncties.

---

### ✅ Epic 17: Goal-Specific Blueprints (Afgerond)

Hardcoded sportwetenschappelijke regels per discipline — coaching op basis van bewezen principes, niet alleen AI-gevoel.

* **Sprint 17.1 — Architectuur & Harde Regels:** `GoalBlueprint` struct met `minLongRunDistance`, `taperPeriodWeeks`, `weeklyTrimpTarget` en `essentialWorkouts`. Hardcoded Marathon Blueprint (28+32 km), Halve Marathon (16+18 km) en Fietstocht (60+100 km — bijv. Arnhem–Karlsruhe). `BlueprintChecker` detecteert blueprint-type via sleutelwoorden of SportCategory-fallback. Unit tests: `BlueprintCheckerTests.swift` (10 tests) + `PeriodizationEngineTests.swift` (14 tests).
* **Sprint 17.2 — LLM Integratie:** Blueprint-milestones + periodization-context geïnjecteerd in alle AI-prompts. `[PERIODISERING]` blok met fase-coaching boodschap, succescriteria en TRIMP-targets.
* **Sprint 17.3 — Milestone UI:** `PhaseBadgeView` boven het schema, `MilestoneProgressCard` met voortgangsbalken per doel. `reasoning`-veld per workout in `WorkoutCardView`.

---

### ✅ Epic 21: Externe Factoren — Weer & Slaap (Afgerond)

Contextuele coaching op basis van omgevingsfactoren die prestatie en herstel direct beïnvloeden.

* **Sprint 21.1 — Open-Meteo Weersverwachting:** `WeatherManager` haalt via de gratis [Open-Meteo API](https://open-meteo.com) de 7-daagse dagelijkse weersverwachting op (temperatuur, neerslag, windsnelheid, WMO-weercode). Geen Apple Developer account of WeatherKit capability vereist. WMO-codes vertaald naar Nederlandse beschrijvingen. Coach ontvangt `[WEERSOMSTANDIGHEDEN]` blok met dagwissel-strategie: bij ⚠️ SLECHT BUITENWEER op een sleuteldag kijkt de coach 3 dagen vooruit en wisselt de trainingen expliciet om. Wind >30 km/u triggert automatisch fietssuggestie naar een windstillere dag. `WeatherBadgeView` toont weericon + neerslagkans op elke `WorkoutCardView`.
* **Sprint 21.2 — Slaapfasen (Sleep Stages):** `fetchSleepStages()` haalt `.asleepDeep`, `.asleepREM` en `.asleepCore` op (iOS 16+ Apple Watch). `SleepStages` struct berekent `deepRatio`. `ReadinessCalculator` past strafpunten toe bij onvoldoende diepe slaap (<15%). `DailyReadiness` model uitgebreid met `deepSleepMinutes`, `remSleepMinutes`, `coreSleepMinutes`. `SleepStagesBarView` toont gestapelde balk (indigo/paars/blauw) + kwaliteitslabel in de Vibe Score kaart. Coach ontvangt expliciete instructie bij <15% diepe slaap.

---

### ✅ Epic 17: Goal-Specific Blueprints (Afgerond)

De coach gaat mee de training in — real-time begeleiding tijdens de workout zelf.

* **Sprint 17.1 — Architectuur & Harde Regels:** `GoalBlueprint` struct met `minLongRunDistance`, `taperPeriodWeeks`, `weeklyTrimpTarget` en `essentialWorkouts`. Hardcoded Marathon Blueprint (28+32 km), Halve Marathon (16+18 km) en Fietstocht (60+100 km — bijv. Arnhem–Karlsruhe). `BlueprintChecker` detecteert blueprint-type via sleutelwoorden of SportCategory-fallback. `PeriodizationEngine` evalueert per doel de huidige `TrainingPhase` en toetst recente activiteiten aan fase-specifieke `PhaseSuccessCriteria`. Unit tests: `BlueprintCheckerTests.swift` (10 tests) + `PeriodizationEngineTests.swift` (14 tests).
* **Sprint 17.2 — LLM Integratie:** Blueprint-milestones + periodization-context geïnjecteerd in alle AI-prompts.
* **Sprint 17.3 — Milestone UI:** `PhaseBadgeView` boven het schema, `MilestoneProgressCard` met voortgangsbalken per doel.

---

### ✅ Epic 23: Blueprint Analysis & Future Projections (Afgerond)

De app maakt de lange-termijn voorbereiding inzichtelijk — niet alleen wat je nú doet, maar of je op koers ligt voor de grote dag.

* **✅ Sprint 23.1 — Target Gap Analysis:** `ProgressService` berekent het verschil (gap) tussen het lineaire verwachte trainingsvolume en het werkelijk behaalde volume. `BlueprintGap` struct bevat TRIMP-achterstand, km-achterstand en een concreet bijsturingsadvies ("je hebt X extra TRIMP/week nodig"). `GapAnalysisCardView` toont per doel een voortgangsbalk voor TRIMP en km in de Doelen-tab. Coach ontvangt een `[GAP ANALYSE]` blok met bijstuurinstructies: "We moeten deze week 15% meer volume draaien om weer in lijn te komen met de Marathon Blueprint."
* **✅ Sprint 23.2 — Future Projection Engine:** `FutureProjectionService` berekent het wekelijkse TRIMP-groeitempo (3-weeks sliding window) en extrapoleerttrendlijn naar de Peak Phase-eis (blueprint × 1.30). Veiligheidslimiet: max 10% groei per week. `ProjectionStatus`: `alreadyPeaking / onTrack / atRisk / unreachable`. `GapAnalysisCardView` toont nieuwe 'Prognose'-sectie met gepland vs. verwacht piekdatum + kleur-badge. Coach ontvangt `[PROGNOSE]` blok met instructie om proactief te waarschuwen als het doel "At Risk" is.
* **✅ Sprint 23.3 — Visual Progress Hub + Goal-Centric UI:** `BlueprintTimelineView` gecombineerde lijngrafiek (SwiftUI Charts): 🩶 Ideaal / 🔵 Actueel / 🟠 Prognose · Toggle TRIMP/km · RuleMark 'Vandaag' + fase-grenzen · scrollbaar 16-wekenvenster. `GoalDetailContainer` herstructureert de Doelen-tab in één overkoepelende kaart per doel met vaste secties: 'Huidige Fase & Mijlpalen' → 'Blueprint Voortgang' → 'Prognose & Tijdlijn' → 'Herstelplan' (optioneel). Gebruiker ziet het complete verhaal van een doel in één oogopslag.

---

### ✅ Epic 24: Nutrition & Fueling Engine (Afgerond)

Fysiologisch correcte voedingsadviezen op basis van wie je bent en wat je van plan bent te doen.

* **✅ Sprint 24.1 — Fysiologisch Profiel (Baseline):** `UserProfileService` haalt gewicht, lengte, leeftijd en geslacht op via HealthKit met graceful fallbacks (HealthKit → UserDefaults → generieke standaardwaarden). `NutritionService` berekent het BMR (Mifflin-St Jeor) en de koolhydraten/vocht-behoefte per trainingszone (Zone 2: 0.5 g/min + 500 ml/uur; Zone 4: 1.0 g/min + 800 ml/uur). `[VOEDING & FYSIOLOGIE]` blok geïnjecteerd in elke AI-prompt met concrete gram/ml-adviezen per geplande workout.
* **✅ Sprint 24.2 — Two-Way Sync (Instellingen UI):** HealthKit-schrijfrechten toegevoegd voor `bodyMass` en `height`. `PhysicalProfileSection` in de Instellingen-tab toont leeftijd/geslacht als read-only (HealthKit, vergrendeld) en gewicht/lengte als bewerkbare velden. Wijzigingen worden gesynchroniseerd naar zowel UserDefaults (instant) als HealthKit (async). Bronbadge toont per waarde de herkomst: ❤️ HealthKit / 📱 Lokaal / ⚠️ Standaard.
* **✅ Sprint 24.3 — Voedings UI & Coach-Integratie:** `WorkoutStatsRow` toont fueling-chips (⏱/⚡/💧/🍌) op elke `WorkoutCardView`. `WorkoutFuelingSectionView` in het detailscherm geeft totalen + per-15-min timing-advies (voor/tijdens/na). Anti-double-day regel toegevoegd aan de coach-prompt met conflictresolutie-prioriteiten.

---

### ✅ Epic 27: Test Coverage Verbeteren (Afgerond)

De unit test coverage van de core services verhogen naar een solide standaard. Focus ligt op services die fysiologische berekeningen en gebruikersprofiel-logica bevatten — code die hoge correctheidseisen heeft en tot nu toe onvoldoende gedekt was.

* **FutureProjectionService:** Tests voor het trendlijn-algoritme (3-weeks sliding window), de veiligheidslimiet (max 10% groei/week) en alle vier `ProjectionStatus`-varianten (`alreadyPeaking / onTrack / atRisk / unreachable`).
* **UserProfileService:** Tests voor HealthKit-fallback-keten (HealthKit → UserDefaults → standaardwaarden), de BMR-berekening (Mifflin-St Jeor) en het synchronisatiegedrag bij gewijzigde gewichts-/lengtewaarden.
* **Doel:** Coverage verhogen van 62% naar ≥75% voor de core service-laag. Doel niet gehaald: we zijn op 63% uitgekomen.

---

### ✅ Epic #28: Doel-Intentie, Meerdaagse Evenementen & Stretch Goals (Afgerond)

De coach begrijpt niet alleen *wat* je wil bereiken, maar ook *hoe* — afmaken vs. presteren. Meerdaagse evenementen (tochtjes, etappekoersen) krijgen een eigen trainingslogica.

* **Stap 1 — Datamodel Uitbreiding:** Verrijken van het `Goal`/`Event`-model met `EventFormat` (bijv. `.singleDayRace`, `.multiDayStage`), `PrimaryIntent` (`.completion` vs. `.peakPerformance`) en een optioneel `StretchGoal` (bijv. een doeltijd). Type-veilige enums, direct gemapt bij het opslaan — conform het SwiftData Strictness-principe.

* **Stap 2 — PeriodizationEngine Refactor:** De planningslogica aanpassen zodat het schema matcht met de intentie. Bij een meerdaagse tocht krijgt de engine instructie om back-to-back duurtrainingen te plannen (cumulatief herstelgedrag). Het schema prioriteert altijd het `PrimaryIntent` (uitlopen/overleven). Het `StretchGoal` (tempo/tijd) wordt alleen in trainingen geïnjecteerd wanneer de actuele Vibe Score én het herstel dat toelaten.

* **Stap 3 — AI Coach Context:** De system prompt in de Gemini `CoachService` updaten. De AI leert dat een "tocht" om comfort, voeding en pacing draait — niet om racen. Bij een dubbel doel (finish én doeltijd) geldt als harde systeeminstructie: de finishlijn heeft altijd prioriteit boven de doeltijd zodra de atleet vermoeid is.

---

### ✅ Epic #29: Visual Overhaul — 'Serene' Thema (Afgerond)

Een complete redesign van de app naar een rustgevend, minimalistisch thema met volledige ondersteuning voor meerdere kleurthema's, Light & Dark mode en dynamische UI-injectie in alle hoofdcomponenten. Niet alleen kleuren en typografie, maar ook de iconografie en illustraties veranderen naadloos mee met het gekozen thema — de hele visuele laag is thema-bewust.

* **✅ Sprint 29.1 — Theme Engine & State:** `ThemeManager` (ObservableObject) en `Theme` enum geïmplementeerd met cases `Moss`, `Stone`, `Mist`, `Clay`, `Sakura` en `Ink`. Gebruikerskeuze persistent via `UserDefaults`. `ThemeManager` wordt als `@EnvironmentObject` door de hele app-hiërarchie geïnjecteerd vanuit `VibeCoachApp`.

* **✅ Sprint 29.2 — Serene Design System:** Kleurenpaletten gedefinieerd in `ThemeManager` via adaptive `UIColor { traits in }` closures (Light/Dark bewust). Semantische rollen: `primaryAccentColor`, `backgroundColor`, `backgroundGradient`. `SereneIconStyle` ViewModifier voor hiërarchische SF Symbol-rendering. Typografie-helpers voor schaalbare koppen en bodytekst.

* **✅ Sprint 29.3 — Instellingen & UI Injectie:** `ThemePicker` gebouwd in `SettingsView` met visuele kleurstalen en live preview. Dynamische tab-iconen via `ThemeManager.icon(for:)`. Typografie-instellingen (kop/body grootte) opgeslagen in `UserDefaults`.

* **✅ Sprint 29.4 — Global Theme Injection & Refactor:** Alle hardcoded `Color.blue` en `Color.accentColor` referenties in `DashboardView`, `RecoveryPlanActiveBannerView`, `PostWorkoutCheckinCard`, `GoalMilestonesSection` (ContentView.swift), `GoalRowView` (GoalsListView.swift), en `NoAPIKeyView` + `MessageBubble` (ChatView.swift) vervangen door `themeManager.primaryAccentColor`. Elk betrokken component krijgt `@EnvironmentObject var themeManager: ThemeManager`. Gebruikerberichten in de chat en actieknoppen tonen nu de actieve themakleur.

---

### ✅ Epic #30: V2.0 Card-Based UX Overhaul (Afgerond)

Een volledige herontwerp van de drie kernschermen naar een moderne, kaartgebaseerde lay-out. De nadruk ligt op visuele hiërarchie, actiegerichte UI-patronen en een informatiedichte maar rustige presentatie van data.

* **✅ Sprint 30.1 — Dashboard V2:** Transitie naar "floating card" lay-out op een lichte achtergrond (`secondarySystemBackground`). `DashboardHeaderView` met contextuele begroeting + dag/fase/week-indicator. `VibeScoreCardV2` met HRV-, slaap- en VO₂max-sub-metrics als inline badges. `WeekTimelineView` voor directe week-navigatie. `TrendWidgetView` voor 14-daagse trendanalyse. `DashboardBannerView` herbruikbare component vervangt gedupliceerde ACWR-bannercode. Rusthartsslag live opgehaald uit HealthKit naast VibeScore-berekening. Kleurmodus-instelling (light/dark/auto) via `AppStorage`. Build number automatisch gezet via CI (`agvtool`).

* **✅ Sprint 30.2 — Interactive Coach Chat:** Refactor van `ChatView` naar gestructureerde V2.0 coach-kaarten. `CoachV2HeaderView` met live fase-label. `CoachTextCard` ("KORT"), `CoachInsightCard` ("WAT IK ZIE") en `PlanAdjustmentCard` ("AANPASSING IN JE PLAN"). Suggestie-chips onderaan het scherm. Tab-iconen bijgewerkt naar outlined stijl voor consistentie met V2.0 esthetiek. Dummy data achter `#if DEBUG` guard zodat productie-UI alleen echte coach-berichten toont.

* **✅ Sprint 30.3 — Goals V2:** `GoalsListView` omgebouwd van `List` naar card-gebaseerde `ScrollView`. Inline `activeGoalCard` per doel met sport-icoon, fase-balk, risico-indicator, voortgangs- en mijlpaal-secties. `completedGoals` sectie onderaan. Voortgangsbalken per trainingsfase (Base / Build / Peak / Taper) zichtbaar per doelkaart.

* **✅ Bugfixes & Kwaliteit (PR #169):** `ColorColor` typo opgelost in `WorkoutCardView`. `TimeInterval`-wiskunde vervangen door `Calendar.dateComponents` in `DashboardHeaderView` en `ChatView.coachPhaseLabel` (conform CLAUDE.md §3). `recoveryReason` toegevoegd aan `AthleticProfile` met unit tests. UI-testsuite volledig bijgewerkt voor V2.0 (geen `navigationBars` meer — `accessibilityIdentifier`-gebaseerde checks op `DashboardHeaderView`, `GoalsScrollView`, `CoachView`). `testGoalManagement` vereenvoudigd: swipe-delete en GoalRow-navigatie verwijderd (V2.0 card-UI heeft geen List meer). 3 nieuwe `AthleticProfileManagerTests` voor `recoveryReason` (volume-overbelasting, aaneengesloten dagen, nil-geval).

---

### ⏳ Epic #31: V2.0 Onboarding Experience (In Ontwikkeling)

Een 5-schermen tellende, conversie-geoptimaliseerde onboarding flow in de nieuwe Serene/Mos stijl. Maakt gebruik van 'live visuals' (mock-UI componenten) in plaats van statische illustraties om de waarde van de app te demonstreren voordat cruciale permissies (HealthKit, Notificaties) worden gevraagd.

* **⏳ Sprint 31.1 — State & Navigatie-structuur:** Setup van `@AppStorage("hasCompletedOnboarding")` in de root van de app. Implementatie van een `TabView` met `PageTabViewStyle` (of een custom step-navigatie) en de herbruikbare layout-wrapper (voortgangsbalk boven, hoofdtitel, dynamische content-area, vaste knoppen-layout onder).

* **⏳ Sprint 31.2 — Live Visuals & Mockups:** Bouwen van de specifieke content-views voor de 5 schermen: Welkom (Hero icon), Uitleg (Mock Vibe Score & TRIMP grafiek), AI Setup (Provider toggle & kosten-uitleg), HealthKit (Permissie visual), Notificaties (Mock iOS notificatie bubble).

* **⏳ Sprint 31.3 — Permissie Logica & Afronding:** Koppelen van de 'Koppel Apple Health' en 'Sta notificaties toe' knoppen aan de daadwerkelijke systeem-prompts. Verfijnen van de copy en de transities.

---

### ⏳ Epic #32: Deep-Dive Fysiologische Analyse (Backlog)

Van gemiddelden naar granulaire fysiologische patronen. De coach analyseert niet langer alleen de samenvatting van een workout, maar leest het volledige verhaal uit de ruwe tijdreeksdata — zodat fenomenen als aerobe ontkoppeling en cadans-verloop zichtbaar en bespreekbaar worden.

* **⏳ Story 32.1 — Time-Series Data Pipeline:** Breid de data-sync uit (HealthKit/Strava) om gedetailleerde samples op te halen van hartslag, vermogen, snelheid en cadans (per 5–10 seconden) in plaats van alleen gemiddelden. Granulaire opslag als aparte `@Model` voor workout-samples met efficiënte query-paden.

* **⏳ Story 32.2 — Annotated Charts UI:** Ontwikkel een interactieve grafiek-interface (met Swift Charts) die meerdere datastromen over elkaar kan leggen. De coach moet specifieke tijdstempels kunnen 'pinnen' met annotaties (bijv. "hier begon de ontkoppeling"), zodat inzichten direct zichtbaar blijven in het workout-detail.

* **⏳ Story 32.3 — AI Pattern Recognition:** Update de AI-prompting zodat de coach specifiek zoekt naar fysiologische fenomenen zoals ontkoppeling (decoupling), cadans-verloop en herstelvermogen tijdens intervallen. Detecteerde patronen worden als annotaties op de grafiek én als contextuele coaching-insights naar de gebruiker gecommuniceerd.

---

### ⏳ Epic #33: Geavanceerde Sessie-architectuur (Backlog)

Trainingen zijn geen uniforme 'workouts' meer, maar sessies met een expliciete fysiologische intentie. De app onderscheidt sessie-typen, laat de gebruiker sessies flexibel ruilen zonder de weekbelasting te verpesten, omarmt sociale ritten als volwaardige herstel-bouwstenen en evalueert achteraf of de intentie ook daadwerkelijk is uitgevoerd.

* **⏳ Story 33.1 — Sessie-Type Taxonomie:** Breid het datamodel uit zodat elke training een specifiek type kan hebben: `VO2maxSession`, `TempoRun`, `LongRun`, `Intervals`, `SocialRideRun`, en `Recovery`. Type-veilige enums conform CLAUDE.md §2, direct gemapt bij het opslaan — geen ruwe strings.

* **⏳ Story 33.2 — Flexibele Planning (The 'Swap'):** Ontwikkel een UI-actie waarmee de gebruiker een geplande sessie kan 'swappen'. Bijvoorbeeld: vervang een voorgestelde 'Tempo' door een 'Social Ride'. De coach herberekent de resterende weekbelasting (TRIMP) automatisch en past de overige sessies aan zodat het weekdoel nog steeds binnen bereik blijft.

* **⏳ Story 33.3 — Sociale Modus:** Implementeer een specifieke logica voor sociale ritten. De coach beoordeelt hierbij de fysiologische data (HRV/HR) minder streng op zones en focust meer op de positieve impact op mentaal herstel en de Vibe Score. Een sociale rit mag de trainingsdag dus niet 'verpesten' in de analyse.

* **⏳ Story 33.4 — Intentie vs. Uitvoering:** Update de analyse-engine. Na de training vergelijkt de coach het geplande type (bijv. VO2max) met de werkelijkheid (bijv. was de hartslag hoog genoeg, de interval-verhouding gehaald?) en geeft daar specifieke feedback op — inclusief voorstel tot bijsturing als de intentie structureel niet wordt waargemaakt.

---

### ⏳ Epic #34: V2.0 Fit & Finish — UI Polish & Tech Debt (Backlog)

Na de grote V2.0-herontwerpronde (Epic #29 + #30) moeten de puntjes op de i. Kleine layout-bugs bij het scrollen, laatste resterende dummy-data, stugge coach-teksten en spacing-inconsistenties tussen iPhone-formaten — stuk voor stuk geen showstoppers, maar samen het verschil tussen "portfolio-app" en "App Store-waardig".

* **⏳ Story 34.1 — Safe Area & Navigation Headers:** Fix layout-bugs tijdens het scrollen. Zorg dat custom headers netjes een achtergrond-blur (`.background(.regularMaterial)`) krijgen of meescrollen, zodat titels niet onleesbaar onder de iOS statusbalk (klok/batterij) verdwijnen.

* **⏳ Story 34.2 — Hardcoded Data Cleanup:** Loop de recent vernieuwde views na (`CoachView`, `GoalsView`, `DashboardView`) en vervang de laatste resterende UI-dummy-variabelen (zoals hardcoded datums, VO₂max-getallen of namen) door de echte datamodellen of veilige fallbacks.

* **⏳ Story 34.3 — Copywriting & Tekstuele Tweaks:** Pas de placeholder-teksten en stugge zinnen in de app aan naar de definitieve, natuurlijke 'Coach' tone-of-voice. Breng waar nodig een centrale structuur aan voor teksten (bijv. `CoachStrings` enum) zodat copy-wijzigingen niet verspreid door de views hoeven te duiken.

* **⏳ Story 34.4 — UI Consistente Spacing:** Loop de padding en spacing van de nieuwe kaarten na op verschillende schermformaten (iPhone SE vs. Pro Max) om te zorgen dat de layout nergens afbreekt of te krap oogt. Waar zinnig semantische spacing-constants toevoegen in plaats van magic numbers.

---

## Testing Push Notifications in Simulator
Om push-notificaties te testen in de iOS Simulator, kun je een bestand met de naam `test-push.apns` aanmaken en deze letterlijk naar de draaiende simulator slepen (Drag & Drop).

```json
{
  "Simulator Target Bundle": "com.markclausing.aifitnesscoach",
  "aps": {
    "alert": {
      "title": "Nieuwe Workout",
      "body": "🏃‍♂️ Nieuwe Strava activiteit gedetecteerd. Jouw coach analyseert dit..."
    },
    "badge": 1,
    "sound": "default"
  },
  "activityId": 1234567890
}
```
*Zorg ervoor dat het veld `"Simulator Target Bundle"` exact overeenkomt met de Bundle Identifier van je Xcode project.*
*Vervang `1234567890` door een echt Strava Activity ID om een live analyse af te dwingen.*

---

## Technische Beslissingen & Afwijkingen

Korte log van keuzes die afwijken van het originele plan, zodat context niet verloren gaat.

| Beslissing | Reden | Alternatief dat werd overwogen |
|-----------|-------|-------------------------------|
| **Open-Meteo i.p.v. WeatherKit** (Epic 21.1) | WeatherKit vereist een betaald Apple Developer account en een actieve entitlement. Open-Meteo is gratis, geen API-sleutel nodig, en levert dezelfde data (temp, neerslag, wind via WMO-codes). | WeatherKit — uitgesteld tot eventuele App Store release |
| **`deepSleepRatio` als optional parameter** in `ReadinessCalculator` | Oudere Apple Watch-modellen schrijven alleen de generieke `.asleep` waarde, geen fase-uitsplitsing. Nil = geen strafpunt, zodat de calculator ook correct werkt op oudere hardware. | Aparte calculator-variant per device-generatie |
| **Sentinel `"GEEN_BIOMETRISCHE_DATA"`** in AppStorage | Onderscheidt 'geen Watch gedragen vannacht' van 'nog niet berekend'. Coach krijgt expliciete instructie om HRV-zinnen te vermijden als de Watch niet gedragen was. | Extra `@State` boolean (vermeden om SwiftData-race-condition te voorkomen) |

---

## Tech Stack
* **Platform:** iOS (macOS met Xcode vereist voor het bouwen)
* **UI Framework:** SwiftUI + SwiftData
* **AI:** BYOK — Gemini 2.5 Flash (standaard), met UI-support voor OpenAI en Anthropic
* **Data:** Apple HealthKit (HRV, slaap + slaapfases, workouts) + optioneel Strava OAuth2
* **Weer:** Open-Meteo API (gratis, geen API-sleutel) via CoreLocation + URLSession
* **Achtergrond:** HKObserverQuery (Engine A) + BGAppRefreshTask (Engine B)
* **Testen:** XCTest unit tests + XCUITest UI tests — 63% code coverage (target: ≥75%)
* **Versiebeheer:** GitHub

## Basisregels voor de AI (Mijn Assistent)
* Schrijf schone, modulaire SwiftUI code. Verdeel grote schermen in kleinere componenten.
* Houd de interface simpel, modern en native. Gebruik standaard iOS-componenten.
* Leg bij complexe code (zoals API-koppelingen) in het Nederlands uit wat de code doet via comments.
* Bouw stap voor stap: zorg dat de basis werkt voordat we ingewikkelde API's toevoegen.
* Quality Control: Schrijf voor élke nieuwe functionaliteit Unit Tests (XCTest) voor de onderliggende logica. Voor de absolute kern-flows (de 'Happy Paths') schrijven we XCUITest UI-tests, zodat we de belangrijkste interacties borgen zonder de test-suite te traag te maken.
* Documentatie Discipline (README Protocol): Elke Pull Request (PR) MOET een update van deze README.md bevatten in dezelfde commit. Vink afgeronde sprints/taken af (✅), voeg zichtbare wijzigingen toe aan de 'Nieuwe Features' sectie, en werk de Roadmap bij met het eerstvolgende logische doel zodat we altijd vooruit plannen.
