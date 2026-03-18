# ai-fitness-coach
fitness coach app for iphone
# AI Fitness Coach - Project Context & AI Instructies

## Doel van de App
Een iOS-app (gebouwd met SwiftUI) die fungeert als een persoonlijke, slimme fitnesscoach. De gebruiker kan via een chat-interface praten over fitnessdoelen, trainingen analyseren en directe feedback krijgen.

## Kernfunctionaliteiten (Roadmap)
1. **Fase 1: Chat Interface.** Een native iOS chat-scherm vergelijkbaar met iMessage, waar de gebruiker berichten en screenshots kan sturen.
2. **Fase 2: AI Integratie (Gemini).** Koppeling met de Gemini API (tekst) zodat de coach intelligent kan reageren op vragen.
3. **Fase 3: Vision API Integratie.** Gebruik van Gemini's vision-mogelijkheden zodat de coach geüploade screenshots van intervallen of data-overzichten kan 'lezen' en interpreteren.
4. **Fase 4: Proactieve Coach & Doelen.** De introductie van persoonlijke sportdoelen en geautomatiseerde integratie met externe sportplatformen. Deze fase bestaat uit drie deelsprints:
    - **Sprint 4.1: Doelen Tracker (SwiftData).** Een lokale database voor het aanmaken, bewerken en verwijderen van specifieke trainingsdoelen (bijv. "Marathon onder 3:30 op 18 oktober"). De app toont de voortgang en resterende dagen.
    - **Sprint 4.2: Externe API's (Strava / Intervals.icu).** Een beveiligde OAuth koppeling bouwen om ruwe en actuele trainingsdata, zoals hartslag- en vermogensstreams, rechtstreeks in te laden.
    - **Sprint 4.3: 'Update & Analyse' Engine.** Een centrale actie-knop die de actuele externe trainingsdata combineert met de gestelde doelen uit SwiftData, en deze bundel als één uitgebreide context-prompt naar het AI-model (Gemini 3.1 Pro) stuurt voor een gerichte, professionele sportanalyse.
5. **Fase 5: Proactieve AI Coach & Cloud Infrastructuur.** De app transformeert van een "pull" model naar een "push" model, waarbij het proactief reageert op voltooide trainingen.
    - Het opzetten van een lichte backend ('brievenbus') om real-time Strava Webhooks op te vangen.
    - Het versturen van Apple Push Notifications (APNs) naar de iOS app bij een nieuwe training.
    - Het dynamisch laten herberekenen van het trainingsplan (in SwiftData) door Gemini, direct na het voltooien van een training.

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
