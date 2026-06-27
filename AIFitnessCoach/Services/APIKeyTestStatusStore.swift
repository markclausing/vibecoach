import Foundation
import CryptoKit

/// Epic #62 story 62.2 — remembers, per provider, the fingerprint of the last API key that
/// passed the validation ping, so the "key works" verdict survives a provider switch and an
/// app restart. Previously the verdict was `@State`-only and evaporated the moment the user
/// switched provider or relaunched.
///
/// UserDefaults-injected (§6) for testability. Stores only a SHA256 **fingerprint** of the
/// key, never the key itself (§11 privacy) — enough to recognise the exact same key later.
struct APIKeyTestStatusStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func storageKey(for provider: AIProvider) -> String {
        "vibecoach_apiKeyValidated_\(provider.rawValue)"
    }

    /// Stable, non-reversible fingerprint of a key (trimmed first so it matches the stored form).
    static func fingerprint(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Records that `key` validated successfully for `provider`.
    func markValidated(key: String, for provider: AIProvider) {
        defaults.set(Self.fingerprint(key), forKey: storageKey(for: provider))
    }

    /// Clears any stored verdict for `provider` (e.g. after a failed test or a cleared key).
    func clear(for provider: AIProvider) {
        defaults.removeObject(forKey: storageKey(for: provider))
    }

    /// True when `key` is exactly the key last recorded as valid for `provider`.
    func isValidated(key: String, for provider: AIProvider) -> Bool {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let stored = defaults.string(forKey: storageKey(for: provider)) else {
            return false
        }
        return stored == Self.fingerprint(key)
    }
}
