import apn from '@parse/node-apn';
import dotenv from 'dotenv';

dotenv.config();

// Configuratie object voor APNs provider.
// Normaal gesproken gebruik je hier een .p8 bestand en je team id.
// Omdat we nu in de beginfase zitten en .env gebruiken, halen we deze opties deels op uit .env.
const options = {
    token: {
        key: process.env.APN_AUTH_KEY || 'dummy_key', // Het absolute pad naar de .p8 file OF een string representatie
        keyId: process.env.APN_KEY_ID || 'dummy_keyId', // Het Key ID van Apple Developer Portal
        teamId: process.env.APN_TEAM_ID || 'dummy_teamId' // Het Team ID van je Apple Developer account
    },
    production: false // Gebruik sandbox/development voor nu
};

// Initialiseer provider (enkel een instance, probeert te verbinden wanneer we zenden)
// Als je geen key instelt kan new apn.Provider() een fout gooien als dit niet compleet is.
// Echter voor deze test flow zorgen we dat de provider functioneert wanneer de variabelen juist zijn.
let apnProvider = null;
try {
    apnProvider = new apn.Provider(options);
} catch (e) {
    console.error('⚠️ Fout bij initialiseren van APNs provider (missende of foute configuratie):', e.message);
}

/**
 * Verstuurt een test notificatie naar de client app via APNs.
 */
export const sendTestNotification = async (activityId) => {
    // Kijk of we het device token hebben uit de .env file
    const deviceToken = process.env.TEST_DEVICE_TOKEN;

    if (!deviceToken) {
        console.warn('⚠️ Geen TEST_DEVICE_TOKEN gevonden in .env. APN wordt overgeslagen.');
        return;
    }

    if (!apnProvider) {
        console.warn('⚠️ APNs Provider is niet succesvol geïnitialiseerd. APN wordt overgeslagen.');
        return;
    }

    // Stel een Notificatie op
    const note = new apn.Notification();

    note.expiry = Math.floor(Date.now() / 1000) + 3600; // Verloopt 1 uur na verzenden
    note.badge = 1;
    note.sound = 'ping.aiff';
    note.alert = `🏃‍♂️ Nieuwe Strava activiteit gedetecteerd (ID: ${activityId}). Jouw coach analyseert dit...`;
    note.topic = process.env.APN_BUNDLE_ID || 'nl.aifitnesscoach.app'; // Moet matchen met de App Bundle ID

    // Custom data in de payload, voor later (Fase 5.3) om SwiftData update te triggeren
    note.payload = { 'activityId': activityId };

    console.log(`📡 Verzenden van APNs pushbericht naar device token (eindigt op: ...${deviceToken.slice(-4)})...`);

    try {
        const result = await apnProvider.send(note, deviceToken);

        if (result.sent.length > 0) {
            console.log('✅ APNs pushbericht succesvol verzonden!');
        }

        if (result.failed.length > 0) {
            console.error('❌ APNs pushbericht verzenden mislukt:', JSON.stringify(result.failed, null, 2));
        }
    } catch (err) {
         console.error('❌ Onverwachte fout tijdens versturen APNs:', err);
    }
};
