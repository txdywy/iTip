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

    // MARK: - Concurrency Stress Test

    /// Verify that concurrent calls to recordActivation and flush do not crash.
    /// The syncQueue inside ActivationMonitor should serialize all access.
    func testConcurrentRecordActivationAndFlushDoesNotCrash() {
        let store = InMemoryUsageStore()
        let monitor = makeMonitor(store: store)

        let iterations = 200
        let expectation = expectation(description: "All concurrent operations complete")
        expectation.expectedFulfillmentCount = iterations * 2

        // Spawn concurrent recordActivation calls
        for i in 0..<iterations {
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.recordActivation(
                    bundleIdentifier: "com.test.app\(i % 10)",
                    displayName: "App \(i % 10)"
                )
                expectation.fulfill()
            }
        }

        // Spawn concurrent flush calls
        for _ in 0..<iterations {
            DispatchQueue.global(qos: .utility).async {
                monitor.flush()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Final flush to persist all pending data
        monitor.flush()

        let records = try! store.load()
        // We should have exactly 10 distinct apps (app0..app9)
        XCTAssertEqual(records.count, 10)
        // Total activation count across all records should equal iterations
        let totalActivations = records.reduce(0) { $0 + $1.activationCount }
        XCTAssertEqual(totalActivations, iterations)
    }

    // MARK: - Duration Tracking Test

    /// Verify that switching from app A to app B accumulates foreground time on A.
    func testDurationTrackingAccumulatesForegroundTime() {
        let store = InMemoryUsageStore()
        var currentDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

        let monitor = ActivationMonitor(
            store: store,
            notificationCenter: NotificationCenter(),
            dateProvider: { currentDate },
            selfBundleIdentifier: "com.example.iTip"
        )

        // Activate app A
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        // Advance time by 30 seconds, then switch to app B
        currentDate = currentDate.addingTimeInterval(30)
        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")

        // Advance time by 15 seconds, then switch to app C
        currentDate = currentDate.addingTimeInterval(15)
        monitor.recordActivation(bundleIdentifier: "com.apple.Mail", displayName: "Mail")

        monitor.flush()

        let records = try! store.load()
        let safari = records.first(where: { $0.bundleIdentifier == "com.apple.Safari" })!
        let finder = records.first(where: { $0.bundleIdentifier == "com.apple.Finder" })!
        let mail = records.first(where: { $0.bundleIdentifier == "com.apple.Mail" })!

        // Safari was foreground for 30 seconds (before Finder activated)
        XCTAssertEqual(safari.totalActiveSeconds, 30, accuracy: 0.01)
        // Finder was foreground for 15 seconds (before Mail activated)
        XCTAssertEqual(finder.totalActiveSeconds, 15, accuracy: 0.01)
        // Mail is still the foreground app, no duration accumulated yet
        XCTAssertEqual(mail.totalActiveSeconds, 0, accuracy: 0.01)
    }

    /// Verify that re-activating the same app accumulates total duration correctly.
    func testDurationTrackingAccumulatesAcrossMultipleActivations() {
        let store = InMemoryUsageStore()
        var currentDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

        let monitor = ActivationMonitor(
            store: store,
            notificationCenter: NotificationCenter(),
            dateProvider: { currentDate },
            selfBundleIdentifier: "com.example.iTip"
        )

        // A → B → A pattern
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        currentDate = currentDate.addingTimeInterval(20)

        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")
        currentDate = currentDate.addingTimeInterval(10)

        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        currentDate = currentDate.addingTimeInterval(5)

        // Switch away from Safari to trigger duration accumulation
        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")

        monitor.flush()

        let records = try! store.load()
        let safari = records.first(where: { $0.bundleIdentifier == "com.apple.Safari" })!

        // Safari: 20s (first stint) + 5s (second stint) = 25s
        XCTAssertEqual(safari.totalActiveSeconds, 25, accuracy: 0.01)
        XCTAssertEqual(safari.activationCount, 2)
    }
}
