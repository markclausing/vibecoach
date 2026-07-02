import Foundation

// MARK: - App-internal Notification names
//
// Type-safe replacements for the stringly-typed inline notification-name
// literals that were repeated across the app (Epic 65.1). Referencing the
// constant instead of the raw string removes the typo risk between the poster
// and the observer.
extension Notification.Name {

    /// Posted to ask `AppTabHostView` to run an on-demand auto-sync (HealthKit +
    /// Strava). Fired e.g. on foreground return and after a manual refresh.
    /// The raw value stays `"TriggerAutoSync"` — byte-identical to the previous
    /// inline literal so any already-registered observers keep matching.
    static let triggerAutoSync = Notification.Name("TriggerAutoSync")
}
