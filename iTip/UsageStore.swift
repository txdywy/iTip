import Foundation
import os.log

/// Thread-safety model:
/// All public methods dispatch synchronously onto `queue`, forming a serial
/// execution boundary. The notification is posted *after* the sync block returns
/// so observers never re-enter the queue during the same call.
///
/// Lock ordering: callers must NOT hold any other iTip queue lock when calling
/// UsageStore methods — the store queue is always the innermost lock.
final class UsageStore: UsageStoreProtocol {

    private let storageURL: URL
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "iTip").usageStore")
    private var cachedRecords: [UsageRecord]?

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
            try _loadFromDisk()
        }
    }

    func save(_ records: [UsageRecord]) throws {
        try queue.sync {
            try _saveToDisk(records)
        }
        NotificationCenter.default.post(name: .usageStoreDidUpdate, object: self)
    }

    func updateRecords(_ modify: (inout [UsageRecord]) -> Void) throws {
        try queue.sync {
            var records = try _loadFromDisk()
            modify(&records)
            try _saveToDisk(records)
        }
        NotificationCenter.default.post(name: .usageStoreDidUpdate, object: self)
    }

    // MARK: - Private (must be called on `queue`)

    /// Loads records from disk (or returns cached copy). Must be called on `queue`.
    private func _loadFromDisk() throws -> [UsageRecord] {
        if let cachedRecords = cachedRecords {
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
            os_log("UsageStore: failed to decode records, recovering: %{public}@", log: AppLog.usageStore, type: .error, error.localizedDescription)
            recoverFromCorruption()
            cachedRecords = []
            return []
        }
    }

    /// Encodes and atomically writes records to disk. Must be called on `queue`.
    private func _saveToDisk(_ records: [UsageRecord]) throws {
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

    private func recoverFromCorruption() {
        let backupURL = storageURL.appendingPathExtension("corrupt")
        // Remove any previous corrupt backup
        try? FileManager.default.removeItem(at: backupURL)
        // Rename the current file as backup
        try? FileManager.default.moveItem(at: storageURL, to: backupURL)
        os_log("UsageStore: recovered from corrupt data file, backup saved to %{public}@", log: AppLog.usageStore, type: .fault, backupURL.path)
    }
}
