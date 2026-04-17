import XCTest
@testable import iTip

final class MenuPresenterTests: XCTestCase {

    // MARK: - Empty store produces "No recent apps" + "Quit iTip"

    func testEmptyStoreShowsNoRecentAppsAndQuit() {
        let store = InMemoryUsageStore(records: [])
        let presenter = MenuPresenter(store: store)
        let menu = presenter.buildMenu()

        // Expect: "No recent apps" (disabled), separator, "Quit iTip"
        XCTAssertEqual(menu.items.count, 3)

        let noAppsItem = menu.items[0]
        XCTAssertEqual(noAppsItem.title, "No recent apps")
        XCTAssertFalse(noAppsItem.isEnabled)

        XCTAssertTrue(menu.items[1].isSeparatorItem)

        let quitItem = menu.items[2]
        XCTAssertEqual(quitItem.title, "Quit iTip")
    }

    // MARK: - Menu items match ranked order using known-good bundleIdentifiers

    func testMenuItemsMatchRankedOrderAndCount() {
        let now = Date()
        let records = [
            UsageRecord(bundleIdentifier: "com.apple.Finder", displayName: "Finder",
                        lastActivatedAt: now.addingTimeInterval(-100), activationCount: 5),
            UsageRecord(bundleIdentifier: "com.apple.Safari", displayName: "Safari",
                        lastActivatedAt: now, activationCount: 3),
        ]
        let store = InMemoryUsageStore(records: records)
        let presenter = MenuPresenter(store: store)
        let menu = presenter.buildMenu()

        // Ranked order: Safari (most recent), Finder
        // Expect: 2 app items, separator, "Quit iTip" = 4 items
        XCTAssertEqual(menu.items.count, 4)

        XCTAssertEqual(menu.items[0].representedObject as? String, "com.apple.Safari")
        XCTAssertTrue(menu.items[0].attributedTitle?.string.hasPrefix("Safari") ?? false)

        XCTAssertEqual(menu.items[1].representedObject as? String, "com.apple.Finder")
        XCTAssertTrue(menu.items[1].attributedTitle?.string.hasPrefix("Finder") ?? false)

        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Quit iTip")
    }

    // MARK: - Unresolvable bundleIdentifier entries are omitted

    func testUnresolvableBundleIdentifiersAreOmitted() {
        let now = Date()
        let records = [
            UsageRecord(bundleIdentifier: "com.apple.Safari", displayName: "Safari",
                        lastActivatedAt: now, activationCount: 2),
            UsageRecord(bundleIdentifier: "com.fake.NonExistentApp12345", displayName: "FakeApp",
                        lastActivatedAt: now.addingTimeInterval(-10), activationCount: 10),
        ]
        let store = InMemoryUsageStore(records: records)
        let presenter = MenuPresenter(store: store)
        let menu = presenter.buildMenu()

        // Only Safari should appear; FakeApp is unresolvable
        // Expect: 1 app item, separator, "Quit iTip" = 3 items
        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items[0].representedObject as? String, "com.apple.Safari")
        XCTAssertTrue(menu.items[0].attributedTitle?.string.hasPrefix("Safari") ?? false)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, "Quit iTip")

        // Verify the fake record was cleaned from the store
        let remaining = try! store.load()
        XCTAssertFalse(remaining.contains(where: { $0.bundleIdentifier == "com.fake.NonExistentApp12345" }))
        XCTAssertTrue(remaining.contains(where: { $0.bundleIdentifier == "com.apple.Safari" }))
    }

    // MARK: - Traffic formatting

    func testFormatBytesUsesAdaptiveUnits() {
        XCTAssertEqual(MenuPresenter.formatBytes(512), "512B")
        XCTAssertEqual(MenuPresenter.formatBytes(1536), "1.5KB")
        XCTAssertEqual(MenuPresenter.formatBytes(2_000_000), "1.9MB")
        XCTAssertEqual(MenuPresenter.formatBytes(3_000_000_000), "2.79GB")
    }
}
