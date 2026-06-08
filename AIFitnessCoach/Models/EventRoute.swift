import Foundation

// MARK: - Epic #56: route value types for location-aware weather
//
// A multi-day event (e.g. "Fietsen van Arnhem naar Karlsruhe in 5 dagen") follows a
// route from a start to an end location. We derive an *approximate* per-stage location
// by interpolating along the great-circle between start and end — good enough for a
// "where am I roughly that day" weather forecast, per the product brief.
//
// These are plain Codable value types (no SwiftData). The resolved route is cached
// app-side (UserDefaults) keyed by goal id + a title hash, so we avoid a schema
// migration for what is derived, re-computable data.

/// A geographic coordinate in decimal degrees.
struct GeoCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

/// A resolved start→end route for a multi-day event, with the geocoded place names.
struct EventRoute: Codable, Equatable {
    let start: GeoCoordinate
    let end: GeoCoordinate
    let startName: String
    let endName: String
}
