import XCTest
@testable import AIFitnessCoach

/// Pins the container-init recovery rules that stop a locked background launch from wiping the
/// SwiftData store (Sept 2026 incident, see `ModelStoreRecovery`). File-backed in a temp
/// directory; "locked" is simulated with `chmod 000`, which makes `open(2)` fail the same way
/// data protection does on device.
final class ModelStoreRecoveryTests: XCTestCase {

    private var directory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelStoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("default.store")
    }

    override func tearDownWithError() throws {
        // Restore permissions first, otherwise the chmod-000 fixtures cannot be removed.
        if let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for name in names {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: directory.appendingPathComponent(name).path)
            }
        }
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func writeStoreSet(suffixes: [String] = ModelStoreRecovery.sidecarSuffixes) throws {
        for suffix in suffixes {
            try Data("payload\(suffix)".utf8).write(to: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private func lock(_ suffix: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: storeURL.path + suffix)
    }

    private func fileNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: - decideAction

    func testMissingStoreRebuilds() {
        XCTAssertEqual(ModelStoreRecovery(storeURL: storeURL).decideAction(), .quarantineAndRebuild)
    }

    func testReadableStoreThatFailedToOpenIsQuarantined() throws {
        try writeStoreSet()
        XCTAssertEqual(ModelStoreRecovery(storeURL: storeURL).decideAction(), .quarantineAndRebuild)
    }

    /// The incident: a store that is merely locked must never be treated as corrupt.
    func testUnreadableStoreUsesTemporaryInMemoryStoreAndLeavesFilesUntouched() throws {
        try writeStoreSet()
        try lock("")

        XCTAssertEqual(ModelStoreRecovery(storeURL: storeURL).decideAction(), .useTemporaryInMemoryStore)
        XCTAssertEqual(try fileNames(), ["default.store", "default.store-shm", "default.store-wal"])
    }

    func testOneUnreadableSidecarIsEnoughToKeepTheStore() throws {
        try writeStoreSet()
        try lock("-wal")

        XCTAssertEqual(ModelStoreRecovery(storeURL: storeURL).decideAction(), .useTemporaryInMemoryStore)
    }

    // MARK: - quarantineStore

    func testQuarantineMovesTheWholeSetUnderOneStampAndKeepsContent() throws {
        try writeStoreSet()
        let now = Date(timeIntervalSince1970: 1_789_275_597) // 2026-09-13T04:59:57Z

        let moved = ModelStoreRecovery(storeURL: storeURL).quarantineStore(now: now)

        let stamp = "20260913T045957000"
        XCTAssertEqual(try fileNames(), [
            "default.store-shm.quarantined-\(stamp)",
            "default.store-wal.quarantined-\(stamp)",
            "default.store.quarantined-\(stamp)"
        ])
        XCTAssertEqual(moved.count, 3)
        let restored = try String(contentsOfFile: storeURL.path + "-wal.quarantined-\(stamp)", encoding: .utf8)
        XCTAssertEqual(restored, "payload-wal", "Quarantine must preserve the data, not recreate it.")
    }

    func testQuarantineWithoutSidecarsMovesOnlyTheStore() throws {
        try writeStoreSet(suffixes: [""])

        let moved = ModelStoreRecovery(storeURL: storeURL).quarantineStore(now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(moved.map(\.lastPathComponent), ["default.store.quarantined-19700101T000000000"])
        XCTAssertTrue(ModelStoreRecovery(storeURL: storeURL).existingStoreFiles.isEmpty)
    }

    func testQuarantineKeepsOnlyTheNewestSets() throws {
        let recovery = ModelStoreRecovery(storeURL: storeURL, maxQuarantinedSets: 2)
        for day in 0..<3 {
            try writeStoreSet()
            recovery.quarantineStore(now: Date(timeIntervalSince1970: TimeInterval(day) * 86_400))
        }

        XCTAssertEqual(recovery.quarantinedStamps(), ["19700103T000000000", "19700102T000000000"])
        XCTAssertEqual(try fileNames().count, 6, "Two full sets of store + WAL + SHM remain.")
    }

    // MARK: - Protection class

    /// `.complete` / `.completeUnlessOpen` make a cold background launch on a locked device unable
    /// to open the store — the root cause of the incident. Changing this needs a locked-launch plan.
    func testStoreProtectionAllowsLockedBackgroundLaunches() {
        XCTAssertEqual(ModelStoreRecovery.storeFileProtection, .completeUntilFirstUserAuthentication)
    }
}
