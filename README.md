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

✅ **Fase 1 t/m 5: Fundering & Connectiviteit**
* Setup iOS App (SwiftUI) & SwiftData lokale opslag.
* OAuth2 integratie met Strava API.
* Node.js Backend met Strava Webhook integratie & Apple Push Notifications (APNs).
* Deep-linking: Notificatie opvangen en specifieke workout ophalen op basis van het `activityId`.

✅ **Fase 6: Langetermijngeheugen & Proactieve Coaching**
* Historische Sync, Context Injectie & Proactieve Waarschuwingen (Overtraining risk).

✅ **Fase 7: Apple HealthKit Integratie**
* De Fysiologische Rekenmachine (Berekenen van TSS/TRIMP obv HealthKit data).
* Integratie met Apple HealthKit als primaire databron (100% lokaal, privacy-first).
* Hartslagherstel (HRR), Cardiac Drift en Training Load (TSS) ophalen en zelf berekenen na een workout.

✅ **Fase 8: Interactieve Trainingsplanner & Dashboards**
* ✅ **Sprint 8.1:** Readiness Calculator & Goal Injectie (7-daagse cumulatieve TRIMP en actieve doelen toegevoegd aan de prompt).
* ✅ **Sprint 8.2:** Interactieve Trainingskalender. De app heeft een proactieve, visuele planning met een 7-daagse interactieve kalender in SwiftUI.

✅ **Fase 9: De Intelligente Coach (Afgerond)**
* ✅ **Sprint 9.1: Langetermijngeheugen:** Lokale opslag (SwiftData) van gebruikersvoorkeuren uit de chat (bijv. vaste sportdagen). Deze worden onzichtbaar geïnjecteerd in de AI-context.
* ✅ **Sprint 9.2: Workout Acties:** De `WorkoutCardView` is uitgebreid met native SwiftUI Menu-acties (Overslaan, Alternatief vragen), wat een directe herberekening van het schema triggert.
* ✅ **Sprint 9.3: Dynamische Evaluatie & Fysiologische Targets:** Logica ingebouwd voor post-workout evaluatie via push notificaties. Trainingen bevatten fysiologische JSON-velden (`heartRateZone`, `targetPace`).
* ✅ **Nieuwe Feature - UI Pivot:** De app-architectuur is getransformeerd naar een volwaardige TabBar navigatie. Het Dashboard toont de actuele kalender met "Pull-to-Refresh", de chat is beschikbaar via een zwevende `.sheet` overlay, en instellingen en geheugen hebben eigen tabbladen.
* ✅ **Nieuwe Feature - Performance Baseline:** De app berekent dynamisch het gemiddelde hardlooptempo van de gebruiker op basis van recente `ActivityRecord`s in het `AthleticProfile`, en injecteert deze in de AI-prompts voor realistische doelen.

✅ **Epic 10: Open Source Release (Afgerond)**
* Het project voorbereiden op publieke release.
* Security review (verwijderen van hardcoded secrets).
* Documentatie optimaliseren (zoals deze README en setup instructies).

✅ **Epic 11: Coach UX Refactor & State Management (Afgerond)**
* ✅ **Sprint 11.1: Shared State & UX:** Het 'Vraag de Coach' scherm is opgeschoond door backend logica (technische system prompts) onzichtbaar in te bouwen. `TrainingPlanManager` fungeert nu als Single Source of Truth voor het trainingsschema via de `@EnvironmentObject`.
* ✅ **Sprint 11.2: Smart Expiring Memory:** De AI kan inschatten of een doorgegeven feit (bijv. een blessure) tijdelijk of permanent is. Tijdelijke regels krijgen een vervaldatum (`expirationDate`), welke getoond wordt in de Memory UI. Verlopen regels worden genegeerd in API Payloads.
* ✅ **Sprint 11.3: Centrale TabBar Coach Knop:** De zwevende actieknop (FAB) is verwijderd van het dashboard en vervangen door een native centrale TabBar knop. Door een custom SwiftUI tab-interceptie wordt de AI-coach vanuit elke hoek van de app gestart als overlay sheet, zonder de tab-navigatie flow te breken.

✅ **Epic 12: Visual Progress & TRIMP Analytics (Afgerond)**
* ✅ **Sprint 12.1: Multi-Goal Burndown Chart:** Het Dashboard is uitgebreid met een native Swift Charts burndown grafiek. Per fitnessdoel berekent de AI automatisch de benodigde start-TRIMP, en tekent de UI zowel een ideale afbouwlijn als de actueel behaalde trainingsbelasting. Voorzien van backward compatibility voor legacy doelen. De grafiek is interactief en schuifbaar (iOS 17 focus-window) met een duidelijke visuele hiërarchie en markering voor "Vandaag".
* ✅ **Sprint 12.2: Interactieve TRIMP Explainer:** Een nieuwe educatieve kaart onderaan het dashboard met twee interactieve sliders (Duur & Intensiteit). De gebruiker ziet dynamisch en visueel via een exponentiële curve hoe zwaar het doortrainen in hoge hartslagzones weegt op het lichaam.
* ✅ **Sprint 12.3: Predictive Analytics:** De Burndown Chart toont nu per doel via een Swipeable Carousel (Paging) een voorspellende 'Forecast'-lijn. De prognose is hybride: hij kijkt eerst naar de geplande TRIMP uit het actuele weken-schema (`TrainingPlanManager`). Is het schema leeg? Dan valt hij terug op de historische Burn Rate van de laatste 14 dagen. Tevens is er Auto-Sync toegevoegd (die de laatste 14 dagen data laadt bij App Launch en Refresh) én is er een Simulator-Only Developer Tool gebouwd om direct test-data in te schieten. Tot slot past de grafiek "Historical Retroactive Progress" (Optie A) toe: prestaties van vóór de aanmaakdatum van het doel worden met terugwerkende kracht geplot om het startpunt logisch mee te laten schalen met eerder behaalde TRIMP-scores.

✅ **Bugfixes Dashboard & Coach (Afgerond)**
* ✅ **Fix: Pull-to-Refresh hint correct geplaatst:** De "Swipe omlaag om te verversen" hint is teruggezet via `.safeAreaInset(edge: .top)` op de ScrollView, zodat hij niet langer overlapt met de NavigationTitle maar netjes erboven hangt.
* ✅ **Fix: Retry logica bij tijdelijke API-fouten:** Bij een 503-fout (server overbelast) probeert de app automatisch tot 3x opnieuw, met 2 seconden tussenruimte. De loading-indicator toont tijdens een retry een oranje statusmelding ("Server tijdelijk overbelast, opnieuw proberen (1/3)...") in zowel de Chat als het Dashboard.
* ✅ **Fix: Betere foutafhandeling Gemini API:** Specifieke fouten (`promptBlocked`, `invalidAPIKey`, `internalError`) worden netjes afgevangen met gebruiksvriendelijke Nederlandse meldingen zonder technische details.
* ✅ **Fix: Concurrency guard:** Een guard in `sendMessage` voorkomt dat de gebruiker een nieuw bericht stuurt terwijl de coach nog bezig is.

✅ **Epic 13: Proactive Coaching Engine (Afgerond)**
* ✅ **Sprint 13.1: In-app Waarschuwingsbanner:** Een prominente rode banner verschijnt bovenaan het Dashboard zodra een doel significant achteroploopt (burn rate < 75% van benodigde rate). Toont het tekort per doel en een directe "Vraag de Coach"-knop.
* ✅ **Sprint 13.2: Dual Engine Notificatie Architectuur:**
  * **Engine A (Action Trigger):** `HKObserverQuery` + `enableBackgroundDelivery` — iOS wekt de app bij elke nieuwe workout. De app checkt of een doel nog op rood staat en stuurt een contextuele pushnotificatie met directe link naar de coach.
  * **Engine B (Inaction Trigger):** `BGAppRefreshTask` via `BGTaskScheduler` — dagelijkse stille achtergrondcheck. Als de gebruiker 2+ dagen inactief is én een doel op rood staat, volgt een motivatienotificatie.
  * **Architectuur:** `ProactiveNotificationService` (singleton) beheert beide engines. De risicodata wordt gecached in `UserDefaults` vanuit `DashboardView` zodat de engines geen SwiftData-toegang nodig hebben in de achtergrond. Een 24-uurs cooldown voorkomt notificatiespam. Tikken op een notificatie opent direct de AI-coach.
* ✅ **Sprint 13.3: Proactieve Interventie & Herstelplan (Action Phase):**
  * **Debug Trigger:** Knop 'Forceer Achtergrond Sync (Debug)' toegevoegd in Instellingen (`#if DEBUG`). Simuleert exact de logica van Engine A én Engine B, inclusief cooldown-reset — zodat de volledige notificatieflow testbaar is zonder te wachten op een echte iOS achtergrondwake-up.
  * **Recovery Context Injectie:** `ChatViewModel.requestRecoveryPlan()` bouwt automatisch een gedetailleerde prompt met per doel: naam, actuele TRIMP/week, benodigde rate, wekelijks tekort en weken resterend. De AI krijgt instructies om een concreet 7-daags bijgestuurd schema te produceren.
  * **'Los dit op'-knop:** De waarschuwingsbanner heeft twee acties: 'Los dit op' (stuurt recovery context naar AI, opent chat direct met schema-output) en 'Open Chat' (vrij gesprek).
  * **Herstelplan Actief Banner:** Na het drukken op 'Los dit op' verandert de rode banner 3 dagen lang in een blauwe bevestigingsbanner ("Herstelplan Actief") via een `AppStorage` timestamp — zodat de rode foutmelding verdwijnt zodra de gebruiker actie heeft ondernomen.
  * **Fysiologische Guardrails in AI Prompt:** De recovery prompt bevat nu harde regels: (1) de 10-15% progressieregel (wekelijkse TRIMP nooit meer dan 12% verhogen), (2) horizon-check — meer dan 8 weken tot het evenement? Dan Base Building en geleidelijk uitsmeren, geen paniekcorrectie in één week.
  * **Robuuste JSON-parsing:** `extractCleanJSON()` helper strip markdown code blocks (ook `\`\`\`JSON`) én extraheert het `{…}` blok als de AI ook proza vóór de JSON schrijft. `fallbackMessage` parameter op `fetchAIResponse` voorkomt dat ruwe JSON ooit in de chat zichtbaar wordt.
* ✅ **Sprint 13.4: UX & AI Reasoning Polish:**
  * **Motivation altijd zichtbaar:** Als de AI-JSON succesvol wordt geparsed maar `motivation` leeg is, valt de app terug op de `fallbackMessage`. Zo staat er altijd een menselijke bevestiging in de chat.
  * **Subtielere banners:** `ProactiveWarningBannerView` en `RecoveryPlanActiveBannerView` gebruiken nu lichte achtergronden (`Color.orange.opacity(0.12)` / `Color.blue.opacity(0.12)`) met een gekleurde border, zodat ze beter blenden met het native iOS thema.
  * **Rijkere Coach Insights:** De system prompt instrueert de AI nu om een empathische, 2-3 zin uitleg te schrijven die de *waarom* van strategische keuzes benoemt (bijv. cross-training op de fiets om de kuiten te sparen voor een hardloopdoel).
  * **Strengere intensiteitslimieten:** De recovery prompt bevat nu een harde limiet van 60 minuten voor binnensessies én een bewakingsregel tegen extreme TRIMP-pieken ten opzichte van de laatste 7 dagen.

🗄 **Backlog**
* Gamification: beloningen voor het volhouden van schema's.

---

## 🚀 Toekomstige Roadmap (Visie)

Na afronding van Epic 13 (Proactieve Coach) en 13.4 (Polish), evolueert VibeCoach van een TRIMP-tracker naar een **Holistische Performance Coach**. De volgende grote thema's staan op de planning:

### Fysiologische Diepte

✅ **Epic 14: De Readiness Score (HRV & Slaap) (Afgerond)**
* **Doel:** HealthKit data (`heartRateVariabilitySDNN`, `sleepAnalysis`) combineren met TRIMP om een dagelijkse "Vibe/Readiness Score" te berekenen.
* **Coach Impact:** De Dual Engine kan voorafgaand aan een training ingrijpen ("Je zenuwstelsel is overprikkeld, neem rust") in plaats van achteraf.
* ✅ **Sprint 14.1: HealthKit Fundering (Data ophalen):** Permissies voor `heartRateVariabilitySDNN` en `sleepAnalysis` toegevoegd. Robuuste `fetchRecentHRV()` (gemiddelde HRV afgelopen nacht) en `fetchLastNightSleep()` (daadwerkelijke slaapuren, exclusief 'inBed') functies gebouwd in `HealthKitManager`. Debug-knop in Instellingen print HRV en slaap rechtstreeks naar de Xcode console.
* ✅ **Sprint 14.2: Berekening & Opslag (De Vibe Score):** `DailyReadiness` SwiftData model aangemaakt. `ReadinessCalculator` berekent een 0-100 score: slaap (50%, lineair 5-8u) + HRV (50%, vs. 7-daagse persoonlijke baseline). `fetchHRVBaseline(days:)` haalt de vergelijkingsbaseline op. Debug-knop in Instellingen voert upsert uit (max 1 record per dag).
* ✅ **Sprint 14.3: UI & Educatie (Dashboard Integratie):** `VibeScoreCardView` bovenaan het dashboard toont de dagelijkse score (groen ≥80, oranje 50-79, rood <50) met batterij-icoon, slaap- en HRV-data. Fallback naar grijze staat als er nog geen meting is. `VibeScoreExplainerCard` onderaan het dashboard legt het algoritme uit via een inklapbare infokaart.
* ✅ **Sprint 14.4: Brain-Body Connection (AI Prompt Alignment):** De Vibe Score wordt gecached in `AppStorage` via `cacheVibeScore()` en geïnjecteerd in élke AI-prompt (`buildContextPrefix` + `requestRecoveryPlan`). Harde guardrail toegevoegd aan de systeeminstructie: de AI mag de Vibe Score nooit weerspreken en moet hersteladvies UITSLUITEND baseren op de score (≥80 = goed, 50-79 = voorzichtig, <50 = rust afdwingen).

⏳ **Epic 15: Biometrische Context**
* **Doel:** Integratie van externe en interne factoren (bijv. lokale weersomstandigheden (hitte), of hormonale cyclus tracking via HealthKit).
* **Coach Impact:** Schema's aanpassen op verwachte omgevingsstress.

### Strategie & Periodisering

🔄 **Epic 16: Dynamische Periodisering**
* **Doel:** De lineaire 'Burndown Chart' vervangen door een fysiologisch correcte, golvende curve (Base, Build, Peak, Taper).
* **Coach Impact:** De UI en verwachtingen passen zich aan de specifieke trainingsfase aan.
* ✅ **Sprint 16.1: Phase Engine & AI Injectie:** `TrainingPhase` enum (`.baseBuilding`, `.buildPhase`, `.peakPhase`, `.tapering`) met harde AI-instructies per fase. `FitnessGoal.currentPhase` computed property berekent de fase op basis van weken resterend (>12w, 4-12w, 2-4w, <2w). Alle `buildContextPrefix` call sites injecteren nu een `[PERIODISERING]` blok per actief doel. Fase-badge zichtbaar in `GoalRowView` (blauw/oranje/rood/paars).
* ✅ **Sprint 16.2: Fase-Afhankelijke Wiskunde & Statussen:** `TrainingPhase.multiplier` (base=1.0, build=1.15, peak=1.30, taper=0.60) past de lineaire TRIMP-target aan. `GoalRiskStatus` heeft `isTaperingOverload` flag: te hard trainen in taper (>110% van verlaagde target) triggert een rode waarschuwing. `SingleGoalBurndownView` toont de fase-gecorrigeerde "Nodig /wk" waarde inclusief fase-naam. AI-prompt ontvangt nu ook de concrete TRIMP-target na multiplier.

⏳ **Epic 17: Goal-Specific Blueprints**
* **Doel:** AI-prompts uitbreiden met domeinspecifieke regels (bijv. de '32km long-run' regel voor marathons, of voedingsstrategieën voor meerdaagse fietstochten).

### Mentale Belastbaarheid & UX

⏳ **Epic 18: Subjectieve Feedback (RPE)**
* **Doel:** Een korte post-workout slider (Rate of Perceived Exertion) om te meten hoe zwaar de training voelde, onafhankelijk van wat de hartslagmeter zegt.
* **Coach Impact:** Discrepanties tussen lage hartslag en hoge RPE gebruiken als vroege indicator voor overtraining of naderende ziekte.

⏳ **Epic 19: Long-Term Memory & Reflectie**
* **Doel:** Structurele samenvattingen van wekelijkse prestaties en pijntjes (zoals kuitklachten) opslaan.
* **Coach Impact:** De AI kan in toekomstige gesprekken refereren aan prestaties of blessures van maanden geleden.

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