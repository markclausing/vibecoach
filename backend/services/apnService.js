import apn from '@parse/node-apn';
import dotenv from 'dotenv';
import fs from 'fs';

dotenv.config();

let apnProvider = null;

// Initialiseer de APNs provider (alleen als de key file daadwerkelijk bestaat, zodat server lokaal nog opstart zonder keys)
if (process.env.APN_KEY_FILE && fs.existsSync(process.env.APN_KEY_FILE)) {
    const options = {
        token: {
            key: process.env.APN_KEY_FILE, // Path to the .p8 file
            keyId: process.env.APN_KEY_ID,
            teamId: process.env.APN_TEAM_ID
        },
        production: false // Gebruik 'true' in productie of TestFlight. 'false' stuurt naar de APNs sandbox
    };

    apnProvider = new apn.Provider(options);
    console.log('🍏 APNs Provider succesvol geïnitialiseerd.');
} else {
    console.warn('⚠️ APNs Provider NIET geïnitialiseerd. Key file ontbreekt (of APN_KEY_FILE is leeg). Push Notificaties worden niet daadwerkelijk verstuurd.');
}

/**
 * Stuurt een push notificatie naar de iOS app wanneer er een nieuwe activiteit is.
 *
 * @param {string} deviceToken - De hexadecimale APNs device token van de ontvanger
 * @param {string} activityId - Het Strava ID van de nieuwe activiteit
 */
export const sendPushNotification = async (deviceToken, activityId) => {
    if (!deviceToken || deviceToken === 'jouw_device_token_uit_xcode_console') {
        console.error('❌ Ongeldige of ontbrekende device token. Kan push notificatie niet versturen.');
        return;
    }

    const note = new apn.Notification();

    // De zichtbare inhoud van de notificatie
    note.alert = "Nieuwe Strava training gevonden! Tik om door AI te laten analyseren.";
    note.sound = "default";
    // Badge instellen, of evt apns-collapse-id
    note.badge = 1;
    // Onzichtbare payload die in de app kan worden verwerkt (Fase 5 dynamische herberekening)
    note.payload = { 'activityId': activityId };

    // Je iOS app's Bundle Identifier is verplicht als topic
    // Aangezien we dit nu niet in de .env dwingen te zetten, zou je het hier statisch kunnen maken,
    // maar het is beter om het via .env in the voeren of hardcoded voor dit project.
    note.topic = process.env.APN_BUNDLE_ID || "com.example.AIFitnessCoach";

    console.log(`📤 Verzenden van push notificatie naar token: ${deviceToken} voor activity: ${activityId}`);

    if (apnProvider) {
        try {
            const result = await apnProvider.send(note, deviceToken);
            if (result.sent.length > 0) {
                console.log(`✅ Push notificatie succesvol verzonden naar APNs.`);
            }
            if (result.failed.length > 0) {
                console.error(`❌ Fout bij versturen push notificatie:`, JSON.stringify(result.failed, null, 2));
            }
        } catch (error) {
            console.error(`💥 Fout tijdens apnProvider.send:`, error);
        }
    } else {
        console.log(`Mock-modus: Er zou nu een push zijn verstuurd. Configureer .p8 keys in de .env om daadwerkelijk pushberichten te sturen.`);
    }
};
