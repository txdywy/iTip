import Foundation

struct UsageRanker {
    func rank(_ records: [UsageRecord]) -> [UsageRecord] {
        records
            .sorted {
                if $0.lastActivatedAt != $1.lastActivatedAt {
                    return $0.lastActivatedAt > $1.lastActivatedAt
                }
                return $0.activationCount > $1.activationCount
            }
            .prefix(10)
            .map { $0 }
    }
}
