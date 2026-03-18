# ADR 004: Proactive Cloud Architecture (Fase 5)

## Context
De huidige iOS app (AI Fitness Coach) maakt gebruik van een "pull" model om externe trainingsdata (zoals van Strava) op te halen. De app haalt de data pas handmatig op wanneer de gebruiker de app opent en expliciet een analyse aanvraagt via een centrale actie-knop.

Voor een échte, proactieve coach-ervaring in Fase 5 moet de app real-time weten wanneer een gebruiker een training heeft voltooid. Echter, het inbouwen van background polling direct binnen de iOS app is ongewenst. Dit zou leiden tot een onacceptabele drain van de batterij en kan door het iOS besturingssysteem worden geblokkeerd of hevig gelimiteerd. We hebben een architectuur nodig die de gebruiker onmiddellijk kan notificeren via de cloud.

## Decision
We introduceren een lichte backend service (bijv. gebouwd met Node.js of via Cloud Functions) die fungeert als een externe 'brievenbus' voor de app.

1. **Webhook Receiver:** Deze backend zal geconfigureerd worden als een Strava Webhook receiver en vangt events op zodra een training wordt geüpload of verwerkt op het Strava-platform.
2. **Push Notifications:** Bij ontvangst van een relevante webhook stuurt de backend direct een Silent of Visible Push Notification (APNs) naar de iOS app van de betreffende gebruiker.
3. **Dynamische Herberekening:** Zodra de iOS app de push notificatie ontvangt, wordt er (al dan niet op de achtergrond) een gerichte request gedaan naar Gemini om de lokale trainingsplannen en doelen (in SwiftData) proactief te updaten, waarna de gebruiker direct feedback krijgt van de AI coach.

## Consequences (Gevolgen)

* **Positief:**
  * Enorm verbeterde User Experience (UX): de coach voelt echt persoonlijk en proactief aan.
  * Realtime coaching: analyses zijn direct na het sporten beschikbaar.
  * Geen batterij-drain doordat we zware background polling op de iPhone vermijden.

* **Negatief/Complexiteit:**
  * We introduceren een compleet nieuw component in de stack (de backend) dat gehost, gemonitord en onderhouden moet worden.
  * Er is een betaald Apple Developer Program account vereist voor het genereren en verzenden van APNs (Apple Push Notifications).
  * We moeten extra complexiteit inbouwen voor webhook-beveiliging en veilig token-management tussen de backend en de frontend (iOS app).

* **Privacy & Security:**
  * Omdat we nu activiteitsdata via een externe backend routeren in plaats van puur lokaal te werken, moeten we garanderen dat de payloads (zoals Strava IDs en Webhook events) veilig, stateless en vluchtig verwerkt worden.
  * Er wordt geen onnodige ruwe gebruikersdata (zoals hartslag-streams of GPS-coördinaten) in de cloud backend opgeslagen; de backend dient enkel als signaal-routering. De daadwerkelijke data-ophaling en analyse-prompts met AI blijven in principe gecoördineerd vanuit de (lokale of serverloze) veilige omgeving van de gebruiker.
