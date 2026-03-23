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

⏳ **Fase 9: Productie & Lancering (Huidig / Gepland)**
* **Sprint 9.0: De Intelligente Coach (Huidig)**
  * [ ] **9.1 Langetermijngeheugen (Context Injectie):** Opzetten van een lokale opslag (bijv. SwiftData) om gebruikersvoorkeuren uit de chat (zoals vaste sportdagen) op te slaan en deze onzichtbaar te injecteren in de `system_instruction` van elke Gemini API-call.
  * [ ] **9.2 UI: Workout Acties (Vervangen vs. Overslaan):** De `WorkoutCardView` uitbreiden met een menu of swipe-acties, zodat de gebruiker expliciet kan kiezen tussen een 'Rest Day' (uitsmeren van belasting) of een 'Alternatief' (vergelijkbare trainingsprikkel).
  * [ ] **9.3 Dynamische Evaluatie (Post-Workout):** Logica bouwen om voltooide trainingen (nieuwe HealthKit/Strava data) te detecteren en Gemini te triggeren om het resterende weekschema te valideren en waar nodig te herberekenen.
* Echte APNs, Cloud Hosting, TestFlight.

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
