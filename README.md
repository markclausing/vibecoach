# ai-fitness-coach
fitness coach app for iphone
# AI Fitness Coach - Project Context & AI Instructies

## Doel van de App
Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De gebruiker kan via een chat-interface praten over fitnessdoelen, trainingen analyseren en directe feedback krijgen.

## Kernfunctionaliteiten (Roadmap)

✅ **Fase 1 t/m 5: Afgerond.**
* Setup iOS App (SwiftUI) & SwiftData lokale opslag.
* OAuth2 integratie met Strava API.
* Node.js Backend met Strava Webhook integratie & Apple Push Notifications (APNs).
* Deep-linking: Notificatie opvangen en specifieke workout ophalen op basis van het `activityId`.

✅ **Fase 6: Langetermijngeheugen & Proactieve Coaching**
* Historische Sync, Context Injectie & Proactieve Waarschuwingen (Overtraining risk) afgerond.

✅ **Fase 7: Apple HealthKit Integratie**
* De Fysiologische Rekenmachine (Berekenen van TSS/TRIMP obv HealthKit data) is voltooid.
* Integratie met Apple HealthKit als primaire databron (Architectonische Pivot: we hebben Intervals.icu verlaten vanwege API restricties vanuit Strava).
* 100% lokaal, privacy-first, en geen afhankelijkheid van externe API-limieten.
* Hartslagherstel (HRR), Cardiac Drift en Training Load (TSS) ophalen en zelf berekenen na een workout.
* Deze diepe fysiologische data geïnjecteerd in de Gemini prompts.

**Fase 8: Interactieve Trainingsplanner & Dashboards (Afgerond)**
* ✅ **Sprint 8.1: Readiness Calculator & Goal Injectie:** Afgerond (7-daagse cumulatieve TRIMP en actieve doelen toegevoegd aan de prompt).
* ✅ **Sprint 8.2: Interactieve Trainingskalender:** Afgerond. De app heeft een proactieve, visuele planning gekregen met een 7-daagse interactieve kalender in SwiftUI. Gebruikers kunnen voorgestelde trainingen wegdrukken, waarna de AI het resterende schema dynamisch herrekent via structuur JSON-output.

✅ **Fase 9: De Intelligente Coach & UI Pivot (Afgerond)**
* ✅ **Sprint 9.1: Langetermijngeheugen (Context Injectie):** Lokale opslag (SwiftData) van gebruikersvoorkeuren uit de chat (bijv. vaste sportdagen, blessures). Deze worden onzichtbaar geïnjecteerd in de `system_instruction` van elke Gemini API-call, te beheren via een nieuw "Coach Geheugen" scherm.
* ✅ **Sprint 9.2: Workout Acties (Interactieve Kaarten):** De `WorkoutCardView` is uitgebreid met native SwiftUI Menu-acties. Gebruikers kunnen expliciet kiezen om een workout 'Over te slaan' (Rest Day inplannen) of een 'Alternatief' te vragen, wat via dynamische prompts een directe herberekening triggert.
* ✅ **Sprint 9.3: Dynamische Evaluatie & Fysiologische Targets:** Logica ingebouwd voor post-workout evaluatie via push notificaties en "Pull-to-Refresh". Trainingen bevatten nu extra fysiologische JSON-velden (`heartRateZone`, `targetPace`) die in een gedetailleerde bottom-sheet worden getoond.
* ✅ **UI Pivot:** De app-architectuur is succesvol getransformeerd naar een volwaardige TabBar/Dashboard applicatie. Het Dashboard toont de actuele kalender met "Pull-to-Refresh" functionaliteit, de chat is nu beschikbaar via een zwevende .sheet overlay, en instellingen en geheugen hebben eigen tabbladen.
* ✅ **Performance Baseline:** De app berekent nu dynamisch het gemiddelde hardlooptempo (pace) van de gebruiker op basis van recente `ActivityRecord`s in de `AthleticProfileManager` en injecteert deze automatisch in de fysiologische context van de AI-prompts, zodat doelen altijd realistisch zijn.

🚀 **Huidige Status:** De applicatie is architecturaal compleet en staat gemarkeerd als **"Klaar voor Open Source / Public Release"**. (Rest nog: opzetten productie-omgevingen voor APNs en Cloud Hosting indien gewenst).

## Testing Push Notifications in Simulator
Om push-notificaties te testen in de iOS Simulator, kun je een bestand met de naam `test-push.apns` aanmaken en deze letterlijk naar de draaiende simulator slepen (Drag & Drop). De structuur van dit bestand moet er als volgt uitzien:

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
