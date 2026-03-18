# Strava Webhook Receiver (Fase 5 - AI Fitness Coach)

Dit is de lichte "brievenbus" backend service die we gebruiken om push (proactieve) events van Strava te ontvangen wanneer een gebruiker een nieuwe training voltooit.

## Benodigdheden
* Node.js (v18 of nieuwer aanbevolen)
* npm
* ngrok (voor lokaal testen)

## Installatie & Setup

1. **Installeer dependencies:**
   ```bash
   npm install
   ```

2. **Omgevingsvariabelen configureren:**
   Kopieer het `.env.example` bestand naar een nieuw `.env` bestand en vul je geheime Strava Verify Token in.
   ```bash
   cp .env.example .env
   ```

## Server Starten

Start de server lokaal via:
```bash
npm start
```
De server luistert standaard op poort 3000 (of de poort die is ingesteld in je `.env` bestand).

## Lokaal Testen met Ngrok

Om de webhook lokaal te kunnen ontvangen vanuit Strava (wat een publieke URL vereist), kun je ngrok gebruiken:

1. Zorg dat je server lokaal draait (`npm start`).
2. Open een nieuwe terminal en start ngrok op dezelfde poort:
   ```bash
   ngrok http 3000
   ```
3. Kopieer de gegenereerde HTTPS URL (bijv. `https://xxxx-xxx-xx-xxx.ngrok.io`).
4. Gebruik deze URL als webhook Callback URL bij het registreren in het Strava Developer portal (of via cURL). Je endpoint wordt dan: `https://xxxx-xxx-xx-xxx.ngrok.io/webhook`.

## Endpoints

* `GET /webhook` - Handelt de eenmalige verificatie-challenge (subscribe) van Strava af.
* `POST /webhook` - Ontvangt events wanneer sporters activiteiten uploaden. Er zit een filter in dat alleen `activity` (geen profiel of andere) events logt.