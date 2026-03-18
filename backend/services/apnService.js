import apn from '@parse/node-apn';
import dotenv from 'dotenv';

dotenv.config();

// Configuratie voor APNs
// Zorg dat AuthKey_${APN_KEY_ID}.p8 in de root van de backend/ staat of specificeer het juiste pad
let options = {
  token: {
    key: `AuthKey_${process.env.APN_KEY_ID}.p8`, // Verander dit pad indien je p8 file ergens anders staat
    keyId: process.env.APN_KEY_ID,
    teamId: process.env.APN_TEAM_ID
  },
  production: false // Gebruik false voor sandbox/development (Xcode Run), true voor TestFlight/App Store
};

let apnProvider = null;

try {
    apnProvider = new apn.Provider(options);
} catch (error) {
    console.warn("APN Provider kon niet initialiseren (missen er APN credentials of .p8 bestand?):", error.message);
}


export const sendPushNotification = async (deviceToken, activityId) => {
    if (!apnProvider) {
        console.warn("Push Notificatie overgeslagen: APN Provider is niet geconfigureerd.");
        return;
    }

    if (!deviceToken) {
        console.warn("Geen deviceToken meegegeven, push notificatie overgeslagen.");
        return;
    }

    let note = new apn.Notification();

    // De payload van de notificatie
    note.expiry = Math.floor(Date.now() / 1000) + 3600; // Verloopt over 1 uur
    note.badge = 1;
    note.sound = "ping.aiff";
    note.alert = "Nieuwe Strava training gevonden! Tik om door AI te laten analyseren.";
    note.payload = { 'activityId': activityId };
    note.topic = process.env.APN_BUNDLE_ID || "com.example.AIFitnessCoach"; // Je app's bundle ID uit Xcode

    try {
        const result = await apnProvider.send(note, deviceToken);
        if (result.sent.length > 0) {
            console.log(`✅ Push Notificatie succesvol verzonden naar token: ${deviceToken}`);
        }
        if (result.failed.length > 0) {
            console.error(`❌ Fout bij verzenden push notificatie:`, result.failed);
        }
    } catch (error) {
        console.error("Uitzondering bij verzenden APN:", error);
    }
};
