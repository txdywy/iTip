import XCTest
import SwiftCheck
@testable import iTip

// MARK: - Arbitrary conformance for UsageRecord

extension UsageRecord: Arbitrary {
    public static var arbitrary: Gen<UsageRecord> {
        return Gen<UsageRecord>.compose { c in
            let bundleIdentifier = c.generate(using: String.arbitrary.suchThat { !$0.isEmpty })
            let displayName = c.generate(using: String.arbitrary.suchThat { !$0.isEmpty })
            // Generate a reasonable Date range (timeIntervalSinceReferenceDate as Double)
            let timeInterval = c.generate(using: Double.arbitrary.map { abs($0).truncatingRemainder(dividingBy: 1_000_000_000) })
            let lastActivatedAt = Date(timeIntervalSinceReferenceDate: timeInterval)
            let activationCount = c.generate(using: Int.arbitrary.map { abs($0) % 10000 + 1 })
            return UsageRecord(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                lastActivatedAt: lastActivatedAt,
                activationCount: activationCount
            )
        }
    }
}

// MARK: - Property Tests

final class UsageRecordPropertyTests: XCTestCase {

    /// **Validates: Requirements 3.1, 3.3, 9.1, 9.2, 9.3**
    ///
    /// Property 1: UsageRecord 序列化 round-trip
    /// For any valid [UsageRecord] list, encoding with JSONEncoder then decoding
    /// with JSONDecoder SHALL produce an equivalent list.
    func testSerializationRoundTrip() {
        let args = CheckerArguments(maxAllowableSuccessfulTests: 100)
        property("UsageRecord serialization round-trip preserves all data", arguments: args) <- forAll { (records: [UsageRecord]) in
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            guard let data = try? encoder.encode(records) else {
                return false
            }
            guard let decoded = try? decoder.decode([UsageRecord].self, from: data) else {
                return false
            }

            return decoded == records
        }
    }
}
