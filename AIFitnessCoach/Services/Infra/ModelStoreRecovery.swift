import Foundation

/// Decides — and performs — what `AIFitnessCoachApp.makeModelContainer()` does when opening the
/// on-disk SwiftData store fails (CLAUDE.md §12).
///
/// **Why this exists (Sept 2026 incident).** The store used to carry
/// `NSFileProtectionCompleteUnlessOpen`. A *cold* background launch on a locked device — Engine B's
/// `BGAppRefreshTask`, or Engine A's HealthKit background delivery — builds the `ModelContainer`
/// in `App.init`, but a closed `.completeUnlessOpen` file cannot be opened while locked. The init
/// threw, the fallback read that as a corrupt store and **deleted** it — wiping `FitnessGoal`,
/// `UserPreference`, `Symptom` and the workout-chat memory on the maintainer's device, repeatedly.
///
/// Three rules close that hole:
/// 1. **Protection class** — `storeFileProtection` is `.completeUntilFirstUserAuthentication`, so a
///    locked background launch (after the first unlock since boot) can open the store at all.
/// 2. **Unreadable ≠ corrupt** — if the store files exist but cannot be read right now (e.g. a
///    launch before the first unlock), the files are left untouched and the launch runs on a
///    temporary in-memory store. The data is fine; it is merely locked.
/// 3. **Quarantine, never delete** — a store that is readable yet still fails to open (failed
///    migration, real corruption) is moved aside with a timestamp instead of being removed, so it
///    can still be recovered. Only the newest `maxQuarantinedSets` are kept.
///
/// Pure Foundation, no AppStorage/UserDefaults; `FileManager` is injectable (CLAUDE.md §6).
struct ModelStoreRecovery {

    enum Action: Equatable {
        /// The store exists but is not readable right now (data protection before the first
        /// unlock, or file permissions). Never touch the files; run on an in-memory store.
        case useTemporaryInMemoryStore
        /// The store is missing, or readable yet unopenable: quarantine it and build a fresh one.
        case quarantineAndRebuild
    }

    /// File-protection class for the store + WAL/SHM sidecars. Must allow a cold background
    /// launch on a locked device — `.complete` and `.completeUnlessOpen` do not (see type docs).
    static let storeFileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    /// SQLite writes the store as a main file plus WAL/SHM sidecars; they only make sense together.
    static let sidecarSuffixes = ["", "-wal", "-shm"]

    /// Infix between the original file name and the quarantine timestamp.
    static let quarantineMarker = ".quarantined-"

    let storeURL: URL
    let maxQuarantinedSets: Int
    private let fileManager: FileManager

    init(storeURL: URL, maxQuarantinedSets: Int = 2, fileManager: FileManager = .default) {
        self.storeURL = storeURL
        self.maxQuarantinedSets = maxQuarantinedSets
        self.fileManager = fileManager
    }

    /// Store file + whichever sidecars currently exist on disk.
    var existingStoreFiles: [URL] {
        Self.sidecarSuffixes
            .map { URL(fileURLWithPath: storeURL.path + $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// What to do after the container init threw. Call only on that failure path.
    func decideAction() -> Action {
        let files = existingStoreFiles
        guard !files.isEmpty else { return .quarantineAndRebuild }
        // One unreadable member is enough: SQLite cannot open the set without it, and a rebuild
        // would orphan (or destroy) the part that is merely locked.
        return files.allSatisfy(isReadable) ? .quarantineAndRebuild : .useTemporaryInMemoryStore
    }

    /// Moves the store + sidecars aside under one shared timestamp, then prunes older quarantine
    /// sets. Returns the new file URLs. A file that cannot be moved is removed as a last resort,
    /// because leaving it in place would make the fresh-store init open the same broken store again.
    @discardableResult
    func quarantineStore(now: Date = Date()) -> [URL] {
        let stamp = AppDateFormatters.fixed("yyyyMMdd'T'HHmmssSSS", utc: true).string(from: now)
        var moved: [URL] = []
        for source in existingStoreFiles {
            let destination = URL(fileURLWithPath: source.path + Self.quarantineMarker + stamp)
            do {
                try fileManager.moveItem(at: source, to: destination)
                moved.append(destination)
            } catch {
                AppLoggers.fitnessDataService.error("Could not quarantine a store file, removing it instead: \(error.localizedDescription, privacy: .public)")
                try? fileManager.removeItem(at: source)
            }
        }
        pruneQuarantinedSets()
        return moved
    }

    /// Timestamps of the quarantine sets present on disk, newest first.
    func quarantinedStamps() -> [String] {
        let directory = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let stamps = names.compactMap { name -> String? in
            guard name.hasPrefix(prefix), let range = name.range(of: Self.quarantineMarker) else { return nil }
            return String(name[range.upperBound...])
        }
        // The fixed-width timestamp format sorts lexicographically in chronological order.
        return Array(Set(stamps)).sorted(by: >)
    }

    private func pruneQuarantinedSets() {
        let expired = quarantinedStamps().dropFirst(max(maxQuarantinedSets, 0))
        guard !expired.isEmpty else { return }
        let directory = storeURL.deletingLastPathComponent()
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(storeURL.lastPathComponent) {
            guard expired.contains(where: { name.hasSuffix(Self.quarantineMarker + $0) }) else { continue }
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Actually opens the file: data protection makes `open(2)` fail with `EPERM` while the class
    /// key is unavailable, which a permission-bit check like `isReadableFile(atPath:)` would miss.
    private func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }
}
