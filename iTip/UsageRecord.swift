import Foundation

struct UsageRecord: Codable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let lastActivatedAt: Date
    let activationCount: Int
}
