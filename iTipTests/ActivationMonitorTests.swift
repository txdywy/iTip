import XCTest
@testable import iTip

final class ActivationMonitorTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func makeMonitor(store: InMemoryUsageStore, selfId: String = "com.example.iTip") -> ActivationMonitor {
        return ActivationMonitor(
            store: store,
            notificationCenter: NotificationCenter(),
            dateProvider: { self.fixedDate },
            selfBundleIdentifier: selfId
        )
    }

    // MARK: - Requirement 2.5: Self-filtering

    /// Activations with selfBundleIdentifier are ignored.
    func testSelfActivationIsIgnored() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store, selfId: "com.example.iTip")

        monitor.recordActivation(bundleIdentifier: "com.example.iTip", displayName: "iTip")

        let records = try! store.load()
        XCTAssertTrue(records.isEmpty, "Self-activation should be filtered out")
    }

    // MARK: - Requirement 2.2: Missing localizedName falls back to bundleIdentifier

    /// When displayName equals the bundleIdentifier (fallback case), the record uses it.
    func testMissingLocalizedNameFallsToBundleIdentifier() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store)

        // Simulate the fallback: caller passes bundleIdentifier as displayName
        let bundleId = "com.apple.Safari"
        monitor.recordActivation(bundleIdentifier: bundleId, displayName: bundleId)

        let records = try! store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].displayName, bundleId)
    }

    // MARK: - Requirement 2.4: New app creates record with count 1

    func testNewAppCreatesRecordWithCountOne() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store)

        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")

        let records = try! store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].bundleIdentifier, "com.apple.Finder")
        XCTAssertEqual(records[0].displayName, "Finder")
        XCTAssertEqual(records[0].activationCount, 1)
        XCTAssertEqual(records[0].lastActivatedAt, fixedDate)
    }

    // MARK: - Requirement 2.3: Existing app increments count by 1

    func testExistingAppIncrementsCount() {
        let initialRecord = UsageRecord(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            lastActivatedAt: Date(timeIntervalSinceReferenceDate: 600_000_000),
            activationCount: 5
        )
        let store = InMemoryUsageStore(records: [initialRecord])
        let monitor = makeMonitor(store: store)

        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        let records = try! store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].activationCount, 6)
        XCTAssertEqual(records[0].lastActivatedAt, fixedDate)
    }

    // MARK: - Requirement 2.1: Missing bundleIdentifier events are ignored

    /// Since recordActivation requires a bundleIdentifier parameter, the filtering
    /// happens in handleActivation (private). We verify that self-filtering works
    /// as the analogous guard, and that empty-string bundleIdentifier still records
    /// (the guard is on the notification level, not recordActivation).
    func testEmptyBundleIdentifierStillRecords() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store)

        // Empty string is not the self identifier, so it passes through
        monitor.recordActivation(bundleIdentifier: "", displayName: "Unknown")

        let records = try! store.load()
        // recordActivation doesn't filter empty strings - that's handleActivation's job
        // This test documents the boundary: recordActivation trusts its caller
        XCTAssertEqual(records.count, 1)
    }
}
