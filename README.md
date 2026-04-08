# VibeCoach

Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De app combineert Apple HealthKit data, Strava activiteiten en de kracht van de Gemini AI om dynamisch en proactief je trainingsschema's te evalueren en bij te sturen.

---

## 🚀 Huidige Status
**Klaar voor Open Source / Public Release**

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

> Zie Sprint 18.1 & 18.2 details in de commit history.

---

### 🔄 Sprint 19: Tech Debt & UI Testing (Actief)

**Codebase portfolio-ready maken zonder bestaande functionaliteit te breken.**

* Magic numbers vervangen door benoemde constanten (`WorkoutCheckinConfig` enum).
* Accessibility identifiers toegevoegd aan kerncomponenten (`VibeScoreCard`, `RPECheckinCard`, `RPESlider`).
* XCUITest UI-suite uitgebreid: TabBar-structuur, Dashboard rendering, navigatie naar Coach en Doelen, RPE check-in kaart.

---

### 🔄 Epic 18: Subjectieve Feedback — RPE & Mood (Afgerond)

**Hoe zwaar voelde de training?** — onafhankelijk van wat de hartslagmeter zegt.

* **Post-Workout Check-in:** `PostWorkoutCheckinCard` verschijnt bovenaan het dashboard na een echte training (≤48u geleden, ≥15 min, TRIMP ≥15). Bevat een RPE-slider (1–10) en vijf stemming-knoppen (😌 Rustig · 🟢 Goed · 🚀 Sterk · 🤕 Pijn · 🥵 Uitgeput).
* **Noise Filtering:** Woon-werk ritten en korte wandelingetjes onder de drempelwaarden worden automatisch overgeslagen. De 'Negeer'-knop slaat `rpe = 0` op als sentinel zodat de kaart direct verdwijnt zonder de AI-cache te beïnvloeden.
* **Discrepantie-analyse:** De AI ontvangt een `[SUBJECTIEVE FEEDBACK]` blok in iedere prompt. Harde systeeminstructie: laag TRIMP + RPE ≥8 = vroeg waarschuwingssignaal voor overtraining of naderende ziekte — de coach reageert hierop met gedwongen rustadvies.

---

### 📅 Backlog / Toekomstvisie

| Epic | Beschrijving |
|------|--------------|
| **Epic 15 — Biometrische & Omgevingscontext** | Integratie met lokale weersomstandigheden (hitte/kou) en hormonale cyclus via HealthKit voor contextuele TRIMP-weging. |
| **Epic 17 — Goal-Specific Blueprints** | Hardcoded sportwetenschappelijke regels per discipline, zoals 'minimaal één 32 km duurloop voor een marathon', rechtstreeks in de LLM Manager. |
| **Epic 19 — Long-Term Memory** | Wekelijkse AI-samenvattingen van prestaties en terugkerende pijntjes (bijv. kuitklachten) — zodat de coach maanden later nog kan refereren aan chronische patronen. |


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
* **UI Framework:** SwiftUI
* **AI Model:** Gemini Pro API
* **Versiebeheer:** GitHub

## Basisregels voor de AI (Mijn Assistent)
* Schrijf schone, modulaire SwiftUI code. Verdeel grote schermen in kleinere componenten.
* Houd de interface simpel, modern en native. Gebruik standaard iOS-componenten.
* Leg bij complexe code (zoals API-koppelingen) in het Nederlands uit wat de code doet via comments.
* Bouw stap voor stap: zorg dat de basis werkt voordat we ingewikkelde API's toevoegen.
* Quality Control: Schrijf voor élke nieuwe functionaliteit Unit Tests (XCTest) voor de onderliggende logica. Voor de absolute kern-flows (de 'Happy Paths') schrijven we XCUITest UI-tests, zodat we de belangrijkste interacties borgen zonder de test-suite te traag te maken.
* Documentatie Discipline (README Protocol): Elke Pull Request (PR) MOET een update van deze README.md bevatten in dezelfde commit. Vink afgeronde sprints/taken af (✅), voeg zichtbare wijzigingen toe aan de 'Nieuwe Features' sectie, en werk de Roadmap bij met het eerstvolgende logische doel zodat we altijd vooruit plannen.