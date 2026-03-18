import apn from '@parse/node-apn';
import dotenv from 'dotenv';

dotenv.config();

// Configuratie object voor APNs provider.
// Normaal gesproken gebruik je hier een .p8 bestand en je team id.
// Omdat we nu in de beginfase zitten en .env gebruiken, halen we deze opties deels op uit .env.
// Check of alle benodigde echte variabelen aanwezig zijn.
const hasRealCredentials = process.env.APN_AUTH_KEY_PATH && process.env.APN_KEY_ID && process.env.APN_TEAM_ID;

let apnProvider = null;

if (hasRealCredentials) {
    const options = {
        token: {
            key: process.env.APN_AUTH_KEY_PATH, // Het absolute of relatieve pad naar de .p8 file
            keyId: process.env.APN_KEY_ID, // Het Key ID van Apple Developer Portal
            teamId: process.env.APN_TEAM_ID // Het Team ID van je Apple Developer account
        },
        production: false // Gebruik sandbox/development voor nu
    };

    // Initialiseer provider (enkel een instance, probeert te verbinden wanneer we zenden)
    try {
        apnProvider = new apn.Provider(options);
    } catch (e) {
        console.error('⚠️ Fout bij initialiseren van APNs provider (missende of foute configuratie):', e.message);
    }
}

/**
 * Verstuurt een test notificatie naar de client app via APNs (of mockt deze).
 */
export const sendTestNotification = async (activityId) => {
    const deviceToken = process.env.TEST_DEVICE_TOKEN;
    const isSimulatorToken = deviceToken && deviceToken.includes('simulator'); // Een makkelijke heuristiek
    const isMockMode = !hasRealCredentials || !apnProvider || isSimulatorToken;

    if (isMockMode) {
        console.log(`[MOCK APN] 🚀 Mock notificatie verstuurd voor activity ID: ${activityId}`);
        return { success: true, mock: true };
    }

    if (!deviceToken) {
        console.warn('⚠️ Geen TEST_DEVICE_TOKEN gevonden in .env. APN wordt overgeslagen.');
        return;
    }

    // Stel een Notificatie op
    const note = new apn.Notification();

    note.expiry = Math.floor(Date.now() / 1000) + 3600; // Verloopt 1 uur na verzenden
    note.badge = 1;
    note.sound = 'ping.aiff';
    note.alert = `🏃‍♂️ Nieuwe Strava activiteit gedetecteerd (ID: ${activityId}). Jouw coach analyseert dit...`;
    note.topic = process.env.BUNDLE_ID; // Moet matchen met de App Bundle ID

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
