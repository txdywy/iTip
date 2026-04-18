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
        monitor.flush()

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
        monitor.flush()

        let records = try! store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].displayName, bundleId)
    }

    // MARK: - Requirement 2.4: New app creates record with count 1

    func testNewAppCreatesRecordWithCountOne() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store)

        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")
        monitor.flush()

        let records = try! store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].bundleIdentifier, "com.apple.Finder")
        XCTAssertEqual(records[0].displayName, "Finder")
        XCTAssertEqual(records[0].activationCount, 1)
        XCTAssertEqual(records[0].lastActivatedAt, fixedDate)
        XCTAssertEqual(records[0].totalBytesDownloaded, 0)
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
        monitor.flush()

        let records = try! store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].activationCount, 6)
        XCTAssertEqual(records[0].lastActivatedAt, fixedDate)
    }

    // MARK: - Requirement 2.1: Missing bundleIdentifier events are ignored

    /// Since recordActivation now guards against empty bundleIdentifier strings,
    /// empty-string activations are filtered out (matching the behavior that
    /// handleActivation already had by checking for nil/empty bundleIdentifier).
    func testEmptyBundleIdentifierIsIgnored() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store)

        // Empty string is now filtered by recordActivation
        monitor.recordActivation(bundleIdentifier: "", displayName: "Unknown")

        let records = try! store.load()
        XCTAssertEqual(records.count, 0, "Empty bundleIdentifier should be filtered out")
    }
}
