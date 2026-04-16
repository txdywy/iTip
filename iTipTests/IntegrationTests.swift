import XCTest
@testable import iTip

final class IntegrationTests: XCTestCase {

    // MARK: - 10.1 Full data flow: record activation → store save → load → rank → menu build
    // Validates: Requirements 2.3, 2.4, 3.1, 4.1, 5.1, 5.4

    func testFullDataFlowFromActivationToMenuBuild() {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let store = InMemoryUsageStore()

        // Step 1: Create ActivationMonitor with injected date and record activations
        let monitor = ActivationMonitor(
            store: store,
            notificationCenter: NotificationCenter(),
            dateProvider: { fixedDate },
            selfBundleIdentifier: "com.example.iTip"
        )

        // Record two known-good apps (Req 2.4 — new records created)
        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        // Step 2: Verify store persistence (Req 3.1)
        let savedRecords = try! store.load()
        XCTAssertEqual(savedRecords.count, 2)

        // Step 3: Rank the records (Req 4.1 — sorted by lastActivatedAt descending)
        let ranker = UsageRanker()
        let ranked = ranker.rank(savedRecords)
        // Both have the same timestamp, so secondary sort by activationCount (both 1),
        // then stable order. Both have count 1 and same date.
        XCTAssertEqual(ranked.count, 2)

        // Step 4: Build menu from the store (Req 5.1, 5.4)
        let presenter = MenuPresenter(store: store, ranker: ranker)
        let menu = presenter.buildMenu()

        // Menu should have: 2 app items + separator + "Quit iTip" = 4 items
        // (both com.apple.Safari and com.apple.Finder are resolvable on macOS)
        XCTAssertEqual(menu.items.count, 4)
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Quit iTip")

        // Verify the app entries are present
        let titles = menu.items.prefix(2).map { $0.title }
        XCTAssertTrue(titles.contains("Safari"))
        XCTAssertTrue(titles.contains("Finder"))
    }

    func testFullDataFlowWithExistingRecordUpdate() {
        var currentDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let store = InMemoryUsageStore()

        let monitor = ActivationMonitor(
            store: store,
            notificationCenter: NotificationCenter(),
            dateProvider: { currentDate },
            selfBundleIdentifier: "com.example.iTip"
        )

        // Record Finder first (Req 2.4)
        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")

        // Advance time, then record Safari
        currentDate = currentDate.addingTimeInterval(60)
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        // Activate Finder again — should increment count (Req 2.3)
        currentDate = currentDate.addingTimeInterval(60)
        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")

        let records = try! store.load()
        let finderRecord = records.first(where: { $0.bundleIdentifier == "com.apple.Finder" })!
        XCTAssertEqual(finderRecord.activationCount, 2)

        // Rank and build menu — Finder should be first (most recent timestamp)
        let ranker = UsageRanker()
        let presenter = MenuPresenter(store: store, ranker: ranker)
        let menu = presenter.buildMenu()

        XCTAssertEqual(menu.items[0].title, "Finder")
        XCTAssertEqual(menu.items[1].title, "Safari")
    }

    // MARK: - 10.2 Activation → store update → menu refresh
    // Validates: Requirements 2.3, 5.4

    func testActivationUpdatesStoreAndMenuRefreshReflectsNewOrder() {
        var currentDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let store = InMemoryUsageStore()

        let monitor = ActivationMonitor(
            store: store,
            notificationCenter: NotificationCenter(),
            dateProvider: { currentDate },
            selfBundleIdentifier: "com.example.iTip"
        )
        let ranker = UsageRanker()
        let presenter = MenuPresenter(store: store, ranker: ranker)

        // Initial state: record Safari first, then Finder
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        currentDate = currentDate.addingTimeInterval(60)
        monitor.recordActivation(bundleIdentifier: "com.apple.Finder", displayName: "Finder")

        // Build menu — Finder should be first (most recent)
        let menu1 = presenter.buildMenu()
        XCTAssertEqual(menu1.items[0].title, "Finder")
        XCTAssertEqual(menu1.items[1].title, "Safari")

        // Now activate Safari again (Req 2.3 — update existing record)
        currentDate = currentDate.addingTimeInterval(60)
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        // Verify store was updated
        let records = try! store.load()
        let safariRecord = records.first(where: { $0.bundleIdentifier == "com.apple.Safari" })!
        XCTAssertEqual(safariRecord.activationCount, 2)
        XCTAssertEqual(safariRecord.lastActivatedAt, currentDate)

        // Rebuild menu — Safari should now be first (Req 5.4 — fresh data on each open)
        let menu2 = presenter.buildMenu()
        XCTAssertEqual(menu2.items[0].title, "Safari")
        XCTAssertEqual(menu2.items[1].title, "Finder")
    }
}
