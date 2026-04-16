import Foundation

protocol UsageStoreProtocol {
    func load() throws -> [UsageRecord]
    func save(_ records: [UsageRecord]) throws
}
