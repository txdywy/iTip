import Foundation
import os.log

/// Shared `OSLog` instances keyed to `Bundle.main.bundleIdentifier` for Console filtering.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "iTip"

    static let usageStore = OSLog(subsystem: subsystem, category: "UsageStore")
    static let processRunner = OSLog(subsystem: subsystem, category: "ProcessRunner")
    static let networkTracker = OSLog(subsystem: subsystem, category: "NetworkTracker")
    static let memorySampler = OSLog(subsystem: subsystem, category: "MemorySampler")
    static let spotlightSeeder = OSLog(subsystem: subsystem, category: "SpotlightSeeder")
}
