//
//  Secrets.swift
//  AIFitnessCoach
//

import Foundation

enum Secrets {
    static let geminiAPIKey = "VUL_HIER_JE_API_KEY_IN"
    static let stravaClientID = "VUL_HIER_JE_STRAVA_CLIENT_ID_IN"
    static let stravaClientSecret = "VUL_HIER_JE_STRAVA_CLIENT_SECRET_IN"
}

/*
 * Backend Configuratie & Secrets
 * --------------------------------
 * Zorg ervoor dat je in de productieversie ook de onderstaande secrets
 * veilig configureert in de `backend/` map. Verwijder hardcoded keys
 * uit scripts zoals `backend/start.sh` of het Express `server.js` bestand
 * en gebruik een lokaal `.env` bestand.
 *
 * Verwijder of vervang o.a. de volgende hardcoded waarden in je backend scripts:
 *
 * In backend/start.sh:
 * - CLIENT_ID
 * - CLIENT_SECRET
 * - VERIFY_TOKEN (Bijv. de tijdelijke "AIFitnessCoachSecret2026")
 *
 * In backend/.env (voor Apple Push Notifications via server.js):
 * - APN_KEY_ID
 * - APN_TEAM_ID
 * - BUNDLE_ID
 * - TEST_DEVICE_TOKEN
 */
