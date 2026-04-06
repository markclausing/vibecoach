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

🚀 **Epic 12: Advanced Analytics & Motivatie (Actief)**
* Nieuwe grafieken toevoegen aan het Dashboard om progressie te visualiseren (bijv. wekelijkse TRIMP of hartslagzones).
* Gamification: beloningen voor het volhouden van schema's.

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