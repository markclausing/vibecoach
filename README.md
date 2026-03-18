# ai-fitness-coach
fitness coach app for iphone
# AI Fitness Coach - Project Context & AI Instructies

## Doel van de App
Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De gebruiker kan via een chat-interface praten over fitnessdoelen, trainingen analyseren en directe feedback krijgen.

## Kernfunctionaliteiten (Roadmap)

✅ **Fase 1 t/m 4: Fundament & Handmatige AI Coach**
* Setup iOS App (SwiftUI) & SwiftData lokale opslag.
* OAuth2 integratie met Strava API.
* Ophalen van de laatste training en deze handmatig via een chat-interface laten analyseren door de Gemini AI API.

✅ **Fase 5: Automatisering & Push Notificaties**
* Node.js Backend met Strava Webhook integratie.
* Apple Push Notifications (APNs) implementatie met een 'Mock Mode' voor de iOS Simulator.
* Deep-linking: Notificatie opvangen, UI forceren naar de Coach tab, en specifieke workout ophalen op basis van het `activityId`.

⏳ **Fase 6: Langetermijngeheugen & Atletisch Profiel**
* Historische Sync: Knop in Settings om Strava data van de afgelopen 6 maanden op te halen en op te slaan in SwiftData.
* Atletisch Profiel: De iOS app berekent lokaal een profiel (piekprestaties, huidig volume, detraining-status) om als context aan Gemini te voeren.
* Proactieve waarschuwingen: AI laten signaleren bij overtraining of afwijkingen in hartslagzones.

⏳ **Fase 7: Interactieve Trainingsplanner & Dashboards**
* 7-Dagen Planner: Gemini genereert gestructureerde JSON trainingsschema's.
* Interactieve UI: Horizontale kaarten-carrousel in SwiftUI waar de gebruiker trainingen kan wegdrukken, verplaatsen of afvinken.
* AI Herberekening: Direct een nieuw plan genereren als een gebruiker een training wegdrukt.
* Swift Charts: Visuele grafieken van voortgang en hartslagzones.

⏳ **Fase 8: Productie & Lancering**
* Echte APNs certificaten koppelen via Apple Developer Account.
* Node.js backend hosten in de cloud (bijv. Render/Heroku).
* TestFlight distributie.

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
