import XCTest
import SwiftCheck
@testable import iTip

final class UsageRankerPropertyTests: XCTestCase {

    private let ranker = UsageRanker()

    // MARK: - Property 4: Ranking sort correctness

    /// **Validates: Requirements 4.1, 4.2**
    ///
    /// Property 4: Ranking 排序正确性
    /// For any [UsageRecord] list, UsageRanker.rank() output SHALL be sorted
    /// by lastActivatedAt descending, then activationCount descending for equal timestamps.
    func testRankingSortCorrectness() {
        let args = CheckerArguments(maxAllowableSuccessfulTests: 100)
        property("rank() output is sorted by lastActivatedAt desc, then activationCount desc", arguments: args) <- forAll { (records: [UsageRecord]) in
            let ranked = self.ranker.rank(records)

            // Verify each consecutive pair respects the sort order
            for i in 0..<ranked.count where i + 1 < ranked.count {
                let a = ranked[i]
                let b = ranked[i + 1]

                if a.lastActivatedAt == b.lastActivatedAt {
                    // Secondary sort: activationCount descending
                    if a.activationCount < b.activationCount {
                        return false
                    }
                } else if a.lastActivatedAt < b.lastActivatedAt {
                    // Primary sort: lastActivatedAt descending
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Property 5: Ranking idempotency

    /// **Validates: Requirements 4.3**
    ///
    /// Property 5: Ranking 幂等性
    /// For any [UsageRecord] list, rank(records) == rank(rank(records)).
    func testRankingIdempotency() {
        let args = CheckerArguments(maxAllowableSuccessfulTests: 100)
        property("rank() is idempotent: rank(records) == rank(rank(records))", arguments: args) <- forAll { (records: [UsageRecord]) in
            let once = self.ranker.rank(records)
            let twice = self.ranker.rank(once)
            return once == twice
        }
    }

    // MARK: - Property 6: Ranking output count limit

    /// **Validates: Requirements 4.4**
    ///
    /// Property 6: Ranking 输出数量限制
    /// For any [UsageRecord] list of size N (0–20), output length == min(N, 10).
    func testRankingOutputCountLimit() {
        let args = CheckerArguments(maxAllowableSuccessfulTests: 100)
        // Generate lists of size 0–20
        let smallListGen = Gen<Int>.fromElements(in: 0...20).flatMap { size in
            Gen<[UsageRecord]>.compose { c in
                (0..<size).map { _ in c.generate() }
            }
        }
        property("rank() output length equals min(N, 10)", arguments: args) <- forAll(smallListGen) { (records: [UsageRecord]) in
            let ranked = self.ranker.rank(records)
            let expected = min(records.count, 10)
            return ranked.count == expected
        }
    }
}
