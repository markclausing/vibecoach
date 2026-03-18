import express from 'express';
import dotenv from 'dotenv';
import { sendPushNotification } from './services/apnService.js';

dotenv.config();

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const STRAVA_VERIFY_TOKEN = process.env.STRAVA_VERIFY_TOKEN;

// 1. GET /webhook - Verificatie door Strava
app.get('/webhook', (req, res) => {
  // Strava stuurt deze query parameters mee tijdens verificatie
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode && token) {
    if (mode === 'subscribe' && token === STRAVA_VERIFY_TOKEN) {
      console.log('✅ Webhook geverifieerd door Strava!');
      // Beantwoord de challenge met HTTP 200 en de exact ontvangen challenge
      res.status(200).json({ 'hub.challenge': challenge });
    } else {
      console.error('❌ Webhook verificatie mislukt. Tokens komen niet overeen.');
      res.sendStatus(403);
    }
  } else {
    // Geen geldige verificatie request
    res.sendStatus(400);
  }
});

// 2. POST /webhook - Ontvangen van Strava Events
app.post('/webhook', (req, res) => {
  // Stuur *direct* een HTTP 200 terug om Strava te laten weten dat we het bericht hebben.
  // Dit voorkomt dat Strava de webhook als "offline" markeert.
  res.status(200).send('EVENT_RECEIVED');

  const payload = req.body;

  // Filter: we zijn momenteel alleen geïnteresseerd in "activity" (geen "profile" of "athlete" updates)
  if (payload && payload.object_type === 'activity') {
    const objectId = payload.object_id;
    const aspectType = payload.aspect_type; // "create", "update", of "delete"

    console.log(`🏃 Nieuwe Strava activiteit ontvangen!`);
    console.log(`- Type: ${aspectType}`);
    console.log(`- Activity ID: ${objectId}`);
    console.log(`- Volledige payload:`, JSON.stringify(payload));

    // Haal de test device token uit de omgevingsvariabelen
    const testDeviceToken = process.env.TEST_DEVICE_TOKEN;

    // Alleen triggeren bij aanmaak van een nieuwe activiteit
    if (aspectType === 'create') {
        sendPushNotification(testDeviceToken, objectId);
    }
  } else if (payload) {
    console.log(`ℹ️ Ander Strava event ontvangen (niet verwerkt): ${payload.object_type} - ${payload.aspect_type}`);
  }
});

// Start de server
app.listen(PORT, () => {
  console.log(`🚀 Strava Webhook Server luistert op poort ${PORT}`);
  console.log(`Om lokaal te testen, gebruik ngrok: ngrok http ${PORT}`);
});
