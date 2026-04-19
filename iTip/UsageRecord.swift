import Foundation

struct UsageRecord: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    var displayName: String
    var lastActivatedAt: Date
    var activationCount: Int
    /// Cumulative foreground active time in seconds.
    var totalActiveSeconds: TimeInterval
    /// Cumulative downloaded bytes.
    var totalBytesDownloaded: Int64
    /// Latest sampled Resident Set Size (RSS) in bytes.
    var residentMemoryBytes: Int64

    /// Backward-compatible decoding: defaults new fields to 0 if missing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        lastActivatedAt = try container.decode(Date.self, forKey: .lastActivatedAt)
        activationCount = try container.decode(Int.self, forKey: .activationCount)
        totalActiveSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .totalActiveSeconds) ?? 0
        totalBytesDownloaded = try container.decodeIfPresent(Int64.self, forKey: .totalBytesDownloaded) ?? 0
        residentMemoryBytes = try container.decodeIfPresent(Int64.self, forKey: .residentMemoryBytes) ?? 0
    }

    init(bundleIdentifier: String, displayName: String, lastActivatedAt: Date, activationCount: Int, totalActiveSeconds: TimeInterval = 0, totalBytesDownloaded: Int64 = 0, residentMemoryBytes: Int64 = 0) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.lastActivatedAt = lastActivatedAt
        self.activationCount = activationCount
        self.totalActiveSeconds = totalActiveSeconds
        self.totalBytesDownloaded = totalBytesDownloaded
        self.residentMemoryBytes = residentMemoryBytes
    }
}
