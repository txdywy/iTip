import XCTest
@testable import iTip

final class UsageStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var storageURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        storageURL = tempDirectory.appendingPathComponent("usage.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Requirements 3.4: File does not exist → empty array

    func testLoadReturnsEmptyArrayWhenFileDoesNotExist() throws {
        let store = UsageStore(storageURL: storageURL)
        let records = try store.load()
        XCTAssertEqual(records, [])
    }

    // MARK: - Requirements 3.1, 3.2, 3.3: Save then load round-trip

    func testSaveThenLoadRoundTrip() throws {
        let store = UsageStore(storageURL: storageURL)
        let records = [
            UsageRecord(bundleIdentifier: "com.apple.Safari",
                        displayName: "Safari",
                        lastActivatedAt: Date(timeIntervalSinceReferenceDate: 700000000),
                        activationCount: 5),
            UsageRecord(bundleIdentifier: "com.apple.Terminal",
                        displayName: "Terminal",
                        lastActivatedAt: Date(timeIntervalSinceReferenceDate: 700001000),
                        activationCount: 12),
        ]

        try store.save(records)
        let loaded = try store.load()

        XCTAssertEqual(loaded, records)
    }

    // MARK: - Requirements 3.5: Corrupted JSON → recovery

    /// UsageStore now recovers from corrupt files: returns [] and creates .corrupt backup.
    func testLoadRecoversFromCorruptedJSON() throws {
        let corruptedData = Data("not valid json {{{".utf8)
        try corruptedData.write(to: storageURL)

        let store = UsageStore(storageURL: storageURL)
        let records = try store.load()

        // Should return empty array, not throw
        XCTAssertEqual(records, [])

        // A .corrupt backup should have been created
        let backupURL = storageURL.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path),
                      "A .corrupt backup file should be created")

        // The backup should contain the original corrupt data
        let backupData = try Data(contentsOf: backupURL)
        XCTAssertEqual(backupData, corruptedData)
    }

    // MARK: - Corrupt recovery: subsequent saves work

    /// After recovering from corruption, the store should save and load normally.
    func testSaveWorksAfterCorruptRecovery() throws {
        // Write corrupt data
        let corruptedData = Data("{{invalid}}".utf8)
        try corruptedData.write(to: storageURL)

        let store = UsageStore(storageURL: storageURL)

        // Load triggers recovery
        let recovered = try store.load()
        XCTAssertEqual(recovered, [])

        // Now save new data
        let newRecords = [
            UsageRecord(bundleIdentifier: "com.apple.Safari",
                        displayName: "Safari",
                        lastActivatedAt: Date(timeIntervalSinceReferenceDate: 700000000),
                        activationCount: 3),
        ]
        try store.save(newRecords)

        // Create a fresh store instance to bypass cache and verify disk persistence
        let freshStore = UsageStore(storageURL: storageURL)
        let loaded = try freshStore.load()
        XCTAssertEqual(loaded, newRecords)
    }

    // MARK: - Requirements 3.2: Atomic write does not corrupt existing data

    func testAtomicWriteDoesNotCorruptExistingData() throws {
        let store = UsageStore(storageURL: storageURL)
        let original = [
            UsageRecord(bundleIdentifier: "com.apple.Finder",
                        displayName: "Finder",
                        lastActivatedAt: Date(timeIntervalSinceReferenceDate: 700000000),
                        activationCount: 3),
        ]
        try store.save(original)

        // Overwrite with new data
        let updated = [
            UsageRecord(bundleIdentifier: "com.apple.Finder",
                        displayName: "Finder",
                        lastActivatedAt: Date(timeIntervalSinceReferenceDate: 700000000),
                        activationCount: 3),
            UsageRecord(bundleIdentifier: "com.apple.Mail",
                        displayName: "Mail",
                        lastActivatedAt: Date(timeIntervalSinceReferenceDate: 700002000),
                        activationCount: 7),
        ]
        try store.save(updated)

        let loaded = try store.load()
        XCTAssertEqual(loaded, updated)
    }
}
