//
//  Secrets.swift
//  AIFitnessCoach
//

import Foundation

enum Secrets {
    static let stravaClientID = "VUL_HIER_JE_STRAVA_CLIENT_ID_IN"

    // C-01: see Secrets.swift for an explanation. The Worker URL may be shared;
    // the token is a shared secret and does not belong in the public repo.
    static let stravaProxyBaseURL = "https://jouw-worker.example.workers.dev"
    static let stravaProxyToken = "VUL_HIER_JE_CLIENT_SHARED_TOKEN_IN"
}
