import Foundation

protocol UsageStoreProtocol {
    func load() throws -> [UsageRecord]
    func save(_ records: [UsageRecord]) throws
    /// Atomically loads, modifies, and saves records in a single sync block.
    func updateRecords(_ modify: (inout [UsageRecord]) -> Void) throws
}

extension Notification.Name {
    /// Posted after records are persisted to disk.
    static let usageStoreDidUpdate = Notification.Name("com.txdywy.iTip.usageStoreDidUpdate")
}
