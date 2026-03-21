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

✅ **Fase 7: Apple HealthKit Integratie & Hybride Architectuur (Afgerond)**
* Integratie met Apple HealthKit als primaire, lokale databron (Architectonische Pivot vanaf Intervals.icu/Strava).
* Fysiologische Rekenmachine toegevoegd: Lokaal berekenen van de Banister TRIMP (Training Impulse).
* Databron-schakelaar in de instellingen: Gebruikers kunnen zelf kiezen tussen 100% lokaal (HealthKit) of Cloud-API (Strava) voor hun historie en analyses.

**Fase 8: Holistisch Coachen (Huidig)**
* ⏳ **Sprint 8.1: De 7-Dagen Window (Readiness & Prescriptief Advies):** In uitvoering.
* We verschuiven van het analyseren van de *laatste losse sessie* naar het coachen op basis van de opgetelde belasting van de afgelopen 7 dagen.
* De AI beoordeelt de 'Readiness' (actuele vermoeidheid vs. fitheid) en geeft direct prescriptief advies voor de dag zelf (bijv. rust vs. intensieve intervallen).
* 7-Dagen visuele kalender & dashboards (kaarten wegdrukken/aanpassen).
* AI genereert JSON schema's voor de komende week.

⏳ **Fase 9: Productie & Lancering (Gepland)**
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
* Quality Control (TDD): Schrijf voor élke nieuwe functionaliteit of aanpassing altijd direct de bijbehorende Unit Tests (XCTest) in de test target. Geen enkele feature is af zonder werkende tests.
