import Foundation

struct UsageRanker {
    func rank(_ records: [UsageRecord]) -> [UsageRecord] {
        Array(records
            .sorted {
                if $0.lastActivatedAt != $1.lastActivatedAt {
                    return $0.lastActivatedAt > $1.lastActivatedAt
                }
                return $0.activationCount > $1.activationCount
            }
            .prefix(10))
    }
}
