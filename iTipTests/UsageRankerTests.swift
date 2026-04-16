import XCTest
@testable import iTip

final class UsageRankerTests: XCTestCase {

    private let ranker = UsageRanker()

    // MARK: - Requirements 4.1, 4.4: Empty input returns empty output

    func testEmptyInputReturnsEmptyOutput() {
        let result = ranker.rank([])
        XCTAssertEqual(result, [])
    }

    // MARK: - Requirements 4.1, 4.2, 4.4: Fewer than 10 items returns all items sorted

    func testFewerThan10ItemsReturnsAllItemsSorted() {
        let now = Date()
        let records = [
            UsageRecord(bundleIdentifier: "com.a", displayName: "A",
                        lastActivatedAt: now.addingTimeInterval(-300), activationCount: 1),
            UsageRecord(bundleIdentifier: "com.b", displayName: "B",
                        lastActivatedAt: now.addingTimeInterval(-100), activationCount: 3),
            UsageRecord(bundleIdentifier: "com.c", displayName: "C",
                        lastActivatedAt: now, activationCount: 2),
        ]

        let result = ranker.rank(records)

        XCTAssertEqual(result.count, 3)
        // Most recent first
        XCTAssertEqual(result[0].bundleIdentifier, "com.c")
        XCTAssertEqual(result[1].bundleIdentifier, "com.b")
        XCTAssertEqual(result[2].bundleIdentifier, "com.a")
    }

    // MARK: - Requirements 4.4: More than 10 items returns exactly 10

    func testMoreThan10ItemsReturnsExactly10() {
        let now = Date()
        let records = (0..<15).map { i in
            UsageRecord(bundleIdentifier: "com.app\(i)", displayName: "App\(i)",
                        lastActivatedAt: now.addingTimeInterval(Double(i) * 60), activationCount: i + 1)
        }

        let result = ranker.rank(records)

        XCTAssertEqual(result.count, 10)
        // The 10 most recent should be indices 14 down to 5
        XCTAssertEqual(result[0].bundleIdentifier, "com.app14")
        XCTAssertEqual(result[9].bundleIdentifier, "com.app5")
    }

    // MARK: - Requirements 4.1, 4.2: Secondary sort by activation count when timestamps equal

    func testSecondarySortByActivationCountWhenTimestampsEqual() {
        let sameTime = Date()
        let records = [
            UsageRecord(bundleIdentifier: "com.low", displayName: "Low",
                        lastActivatedAt: sameTime, activationCount: 1),
            UsageRecord(bundleIdentifier: "com.high", displayName: "High",
                        lastActivatedAt: sameTime, activationCount: 10),
            UsageRecord(bundleIdentifier: "com.mid", displayName: "Mid",
                        lastActivatedAt: sameTime, activationCount: 5),
        ]

        let result = ranker.rank(records)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].bundleIdentifier, "com.high")
        XCTAssertEqual(result[1].bundleIdentifier, "com.mid")
        XCTAssertEqual(result[2].bundleIdentifier, "com.low")
    }
}
