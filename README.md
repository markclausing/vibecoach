# VibeCoach

Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De app combineert Apple HealthKit data, Strava activiteiten en de kracht van de Gemini AI om dynamisch en proactief je trainingsschema's te evalueren en bij te sturen.

---

## 🚀 Huidige Status
**Portfolio-klaar — Volledig Afgewerkt**

VibeCoach is een production-ready iOS-app met een premium user experience: native splash screen, gepolijste onboarding flow, BYOK AI-architectuur (Gemini / OpenAI / Anthropic), fysiologisch correcte trainingscoaching en een testsuite met 54% code coverage.

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

Uitgebreide opschoning van de codebase. Toevoeging van XCTest Unit- en UI-tests voor de core gebruikersflows en fysiologische rekenmodellen. De testsuite is succesvol afgerond met een Code Coverage van **54%**.

* **Magic Numbers → Constanten:** `WorkoutCheckinConfig` enum centraliseert de RPE check-in drempelwaarden (minimumDurationSeconds, minimumTRIMP, ignoredRPESentinel).
* **Accessibility Identifiers:** Kerncomponenten gemarkeerd (`VibeScoreCard`, `RPECheckinCard`, `RPESlider`, `ChatInputField`, `AddGoalButton`) voor robuuste UI-testbaarheid.
* **UI-testsuite:** 8 XCUITests voor TabBar-volledigheid, Dashboard rendering, navigatie naar Coach/Doelen/Instellingen en de RPE check-in kaart. HealthKit- en notificatie-popups worden gebypassed via `-isRunningUITests` launch argument.
* **Unit Tests (Epic 14 & 16):** `ReadinessCalculatorTests` (8 tests) verifieert grenscases van het Vibe Score algoritme. `TrainingPhaseTests` (11 tests) verifieert fase-detectie, multipliers en fase-gecorrigeerde TRIMP-berekeningen.

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

### 🔄 Epic 17: Goal-Specific Blueprints (Actief)

Hardcoded sportwetenschappelijke regels per discipline — coaching op basis van bewezen principes, niet alleen AI-gevoel.

* **Sprint 17.1 — Architectuur & Harde Regels (Huidig):** `GoalBlueprint` struct met `minLongRunDistance`, `taperPeriodWeeks`, `weeklyTrimpTarget` en `essentialWorkouts`. Hardcoded Marathon Blueprint (verplichte 28 km en 32 km duurlopen), Halve Marathon Blueprint (16 km en 18 km) en Fietsdoel Blueprint (60 km en 100 km duurritten — bijv. Arnhem–Karlsruhe). `BlueprintChecker` detecteert het blueprint-type automatisch via sleutelwoorden in de doeltitel of SportCategory-fallback. Vergelijkt activiteitenhistorie per milestone en retourneert `BlueprintCheckResult` met voldane en openstaande eisen. `ChatViewModel.cacheActiveBlueprints()` injecteert de blueprint-status in alle AI-prompts via het gestandaardiseerde context-prefix systeem. Unit tests in `BlueprintCheckerTests.swift` (10 tests).
* **⏳ Sprint 17.2 — LLM Integratie:** De LLM-manager bewust maken van actieve blueprints voor betere coaching-context en persoonlijk advies.
* **⏳ Sprint 17.3 — Milestone UI:** Visuele weergave van kritieke checkpoints en voortgang op het dashboard.

---

### 📅 Backlog / Toekomstvisie

| Epic | Beschrijving |
|------|--------------|
| **Epic 15 — Biometrische & Omgevingscontext** | Integratie met lokale weersomstandigheden (hitte/kou) en hormonale cyclus via HealthKit voor contextuele TRIMP-weging. |
| **Epic 21 — Long-Term Memory** | Wekelijkse AI-samenvattingen van prestaties en terugkerende pijntjes (bijv. kuitklachten) — zodat de coach maanden later nog kan refereren aan chronische patronen. |
| **Epic 22 — App Store Submission** | Screenshots, App Store beschrijving, Privacy Policy URL, leeftijdsclassificatie en TestFlight beta-distributie. *(Verre toekomst)* |

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

## Tech Stack
* **Platform:** iOS (macOS met Xcode vereist voor het bouwen)
* **UI Framework:** SwiftUI + SwiftData
* **AI:** BYOK — Gemini 2.5 Flash (standaard), met UI-support voor OpenAI en Anthropic
* **Data:** Apple HealthKit (HRV, slaap, workouts) + optioneel Strava OAuth2
* **Achtergrond:** HKObserverQuery (Engine A) + BGAppRefreshTask (Engine B)
* **Testen:** XCTest unit tests + XCUITest UI tests — 54% code coverage
* **Versiebeheer:** GitHub

## Basisregels voor de AI (Mijn Assistent)
* Schrijf schone, modulaire SwiftUI code. Verdeel grote schermen in kleinere componenten.
* Houd de interface simpel, modern en native. Gebruik standaard iOS-componenten.
* Leg bij complexe code (zoals API-koppelingen) in het Nederlands uit wat de code doet via comments.
* Bouw stap voor stap: zorg dat de basis werkt voordat we ingewikkelde API's toevoegen.
* Quality Control: Schrijf voor élke nieuwe functionaliteit Unit Tests (XCTest) voor de onderliggende logica. Voor de absolute kern-flows (de 'Happy Paths') schrijven we XCUITest UI-tests, zodat we de belangrijkste interacties borgen zonder de test-suite te traag te maken.
* Documentatie Discipline (README Protocol): Elke Pull Request (PR) MOET een update van deze README.md bevatten in dezelfde commit. Vink afgeronde sprints/taken af (✅), voeg zichtbare wijzigingen toe aan de 'Nieuwe Features' sectie, en werk de Roadmap bij met het eerstvolgende logische doel zodat we altijd vooruit plannen.