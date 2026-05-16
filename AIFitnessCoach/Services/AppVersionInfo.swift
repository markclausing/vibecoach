import Foundation

/// Epic #51-H2: leest de marketing-versie en build-nummer uit `Bundle.main`
/// en formatteert ze als één string voor de Settings-footer.
///
/// `CFBundleShortVersionString` is de versie die in Info.plist is gepind
/// (matcht `architecture.json#meta.appVersion`). `CFBundleVersion` wordt
/// at-build-time op `git rev-list --count HEAD` gezet door de Build-Phase
/// script (zie ARCHITECTURE.md §11).
enum AppVersionInfo {
    /// Bundle dat in productie altijd `Bundle.main` is; in tests kan een
    /// fixture-bundle geïnjecteerd worden via `displayString(in:)`.
    static var displayString: String {
        displayString(in: .main)
    }

    /// Genereert de format `VibeCoach 2.0.0 (build 627)` uit Bundle-keys.
    /// Bij ontbrekende keys (zou niet horen, maar defensief) toont enkel de
    /// app-naam zonder cijfers — beter een schone string dan "VibeCoach (build )".
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
