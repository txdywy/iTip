import Foundation

struct UsageRanker: Sendable {
    let limit: Int

    init(limit: Int = 10) {
        self.limit = limit
    }

    func rank(_ records: [UsageRecord]) -> [UsageRecord] {
        Array(records
            .sorted {
                if $0.lastActivatedAt != $1.lastActivatedAt {
                    return $0.lastActivatedAt > $1.lastActivatedAt
                }
                return $0.activationCount > $1.activationCount
            }
            .prefix(limit))
    }
}
