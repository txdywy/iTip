import Foundation
import os.log

final class UsageStore: UsageStoreProtocol {

    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.example.iTip.usageStore")
    private var cachedRecords: [UsageRecord]?
    private static let logger = OSLog(subsystem: "com.example.iTip", category: "UsageStore")

    init(storageURL: URL) {
        self.storageURL = storageURL
    }

    /// Convenience initializer using the default storage path:
    /// ~/Library/Application Support/iTip/usage.json
    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("iTip", isDirectory: true)
        let url = directory.appendingPathComponent("usage.json")
        self.init(storageURL: url)
    }

    func load() throws -> [UsageRecord] {
        try queue.sync {
            if let cachedRecords {
                return cachedRecords
            }

            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: storageURL.path) else {
                cachedRecords = []
                return []
            }

            let data = try Data(contentsOf: storageURL)

            do {
                let decoder = JSONDecoder()
                let records = try decoder.decode([UsageRecord].self, from: data)
                cachedRecords = records
                return records
            } catch {
                os_log("Failed to decode usage records: %{public}@", log: UsageStore.logger, type: .error, error.localizedDescription)
                cachedRecords = []
                return []
            }
        }
    }

    func save(_ records: [UsageRecord]) throws {
        try queue.sync {
            let fileManager = FileManager.default
            let directory = storageURL.deletingLastPathComponent()

            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            let data = try encoder.encode(records)
            try data.write(to: storageURL, options: .atomic)
            cachedRecords = records
        }
    }
}
