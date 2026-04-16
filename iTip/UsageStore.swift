import Foundation
import os.log

final class UsageStore: UsageStoreProtocol {

    private let storageURL: URL
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
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([UsageRecord].self, from: data)
        } catch {
            os_log("Failed to decode usage records: %{public}@", log: UsageStore.logger, type: .error, error.localizedDescription)
            return []
        }
    }

    func save(_ records: [UsageRecord]) throws {
        let fileManager = FileManager.default
        let directory = storageURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(records)
        try data.write(to: storageURL, options: .atomic)
    }
}
