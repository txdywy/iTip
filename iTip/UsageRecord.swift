import Foundation

struct UsageRecord: Codable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let lastActivatedAt: Date
    let activationCount: Int
    /// Cumulative foreground active time in seconds.
    let totalActiveSeconds: TimeInterval

    /// Backward-compatible decoding: defaults totalActiveSeconds to 0 if missing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        lastActivatedAt = try container.decode(Date.self, forKey: .lastActivatedAt)
        activationCount = try container.decode(Int.self, forKey: .activationCount)
        totalActiveSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .totalActiveSeconds) ?? 0
    }

    init(bundleIdentifier: String, displayName: String, lastActivatedAt: Date, activationCount: Int, totalActiveSeconds: TimeInterval = 0) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.lastActivatedAt = lastActivatedAt
        self.activationCount = activationCount
        self.totalActiveSeconds = totalActiveSeconds
    }
}
