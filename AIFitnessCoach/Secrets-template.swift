//
//  Secrets.swift
//  AIFitnessCoach
//

import Foundation

enum Secrets {
    static let stravaClientID = "VUL_HIER_JE_STRAVA_CLIENT_ID_IN"

    // C-01: zie Secrets.swift voor uitleg. De Worker-URL mag worden gedeeld;
    // de token is een shared secret en hoort niet in de publieke repo.
    static let stravaProxyBaseURL = "https://jouw-worker.example.workers.dev"
    static let stravaProxyToken = "VUL_HIER_JE_CLIENT_SHARED_TOKEN_IN"
}
