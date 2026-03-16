# ai-fitness-coach
fitness coach app for iphone
# AI Fitness Coach - Project Context & AI Instructies

## Doel van de App
Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De gebruiker kan via een chat-interface praten over fitnessdoelen, trainingen analyseren en directe feedback krijgen.

## Kernfunctionaliteiten (Roadmap)
1. **Fase 1: Chat Interface.** Een native iOS chat-scherm vergelijkbaar met iMessage, waar de gebruiker berichten en screenshots kan sturen.
2. **Fase 2: AI Integratie (Gemini).** Koppeling met de Gemini API (tekst en vision) zodat de coach intelligent kan reageren op vragen en geüploade screenshots van intervallen kan 'lezen'.
3. **Fase 3: Data Integratie.** Automatische koppeling met de API's van Strava en Intervals.icu. De app haalt automatisch de nieuwste hartslag-, wattage- en zone-data op, zodat de AI-coach deze context heeft tijdens het chatten.

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
