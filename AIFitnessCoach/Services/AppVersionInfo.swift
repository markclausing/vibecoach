import Foundation

/// Epic #51-H2: reads the marketing version and build number from `Bundle.main`
/// and formats them as one string for the Settings footer.
///
/// `CFBundleShortVersionString` is the version pinned in Info.plist
/// (matches `architecture.json#meta.appVersion`). `CFBundleVersion` is set
/// at build time to `git rev-list --count HEAD` by the Build Phase
/// script (see ARCHITECTURE.md §11).
enum AppVersionInfo {
    /// Bundle that in production is always `Bundle.main`; in tests a
    /// fixture bundle can be injected via `displayString(in:)`.
    static var displayString: String {
        displayString(in: .main)
    }

    /// Generates the format `VibeCoach 2.0.0 (build 627)` from Bundle keys.
    /// On missing keys (shouldn't happen, but defensive) it shows only the
    /// app name without numbers — a clean string is better than "VibeCoach (build )".
    static func displayString(in bundle: Bundle) -> String {
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "VibeCoach"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (v?, b?): return "\(name) \(v) (build \(b))"
        case let (v?, nil): return "\(name) \(v)"
        case let (nil, b?): return "\(name) (build \(b))"
        case (nil, nil): return name
        }
    }
}
