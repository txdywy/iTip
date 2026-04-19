import Foundation
@testable import iTip

final class InMemoryUsageStore: UsageStoreProtocol {
    private var records: [UsageRecord] = []

    init(records: [UsageRecord] = []) {
        self.records = records
    }

    func load() throws -> [UsageRecord] {
        return records
    }

    func save(_ records: [UsageRecord]) throws {
        self.records = records
        NotificationCenter.default.post(name: .usageStoreDidUpdate, object: self)
    }

    func updateRecords(_ modify: (inout [UsageRecord]) -> Void) throws {
        modify(&records)
        NotificationCenter.default.post(name: .usageStoreDidUpdate, object: self)
    }
}
