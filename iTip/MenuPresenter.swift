import AppKit

final class MenuPresenter {
    private let store: UsageStoreProtocol
    private let ranker: UsageRanker
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Target for app menu item click actions (typically the AppDelegate).
    weak var menuItemTarget: AnyObject?
    /// Selector invoked when an app menu item is clicked.
    var menuItemAction: Selector?

    /// Closure that returns whether activation monitoring is currently active.
    /// When this returns `false`, a permission warning is shown in the menu.
    var isMonitoringAvailable: () -> Bool = { true }

    private var appURLCache: [String: URL?] = [:]
    private var iconCache: [String: NSImage] = [:]

    init(store: UsageStoreProtocol, ranker: UsageRanker = UsageRanker()) {
        self.store = store
        self.ranker = ranker
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Show permission warning if monitoring is not active
        if !isMonitoringAvailable() {
            let warningItem = NSMenuItem(title: "⚠ Monitoring unavailable — check permissions", action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
            menu.addItem(NSMenuItem.separator())
        }

        let records: [UsageRecord]
        do {
            records = try store.load()
        } catch {
            records = []
        }

        let ranked = ranker.rank(records)

        var validRecords: [UsageRecord] = []
        var removedIdentifiers: Set<String> = []

        for record in ranked {
            if cachedURL(for: record.bundleIdentifier) != nil {
                validRecords.append(record)
            } else {
                removedIdentifiers.insert(record.bundleIdentifier)
            }
        }

        // Clean unresolvable records from the store
        if !removedIdentifiers.isEmpty {
            let cleaned = records.filter { !removedIdentifiers.contains($0.bundleIdentifier) }
            try? store.save(cleaned)
            // Invalidate cache for removed apps
            for id in removedIdentifiers {
                appURLCache.removeValue(forKey: id)
                iconCache.removeValue(forKey: id)
            }
        }

        if validRecords.isEmpty {
            let noAppsItem = NSMenuItem(title: "No recent apps", action: nil, keyEquivalent: "")
            noAppsItem.isEnabled = false
            menu.addItem(noAppsItem)
        } else {
            for record in validRecords {
                let item = NSMenuItem(title: "", action: menuItemAction, keyEquivalent: "")
                item.target = menuItemTarget
                item.representedObject = record.bundleIdentifier
                item.attributedTitle = MenuPresenter.attributedTitle(for: record)
                if let appURL = cachedURL(for: record.bundleIdentifier) {
                    item.image = cachedIcon(for: appURL)
                    item.image?.size = NSSize(width: 16, height: 16)
                }
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit iTip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Caching

    private func cachedURL(for bundleIdentifier: String) -> URL? {
        if let cached = appURLCache[bundleIdentifier] {
            return cached
        }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        appURLCache[bundleIdentifier] = url
        return url
    }

    private func cachedIcon(for appURL: URL) -> NSImage? {
        let path = appURL.path
        if let cached = iconCache[path] {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }

    // MARK: - Name Truncation

    private static func truncateName(_ name: String, maxChars: Int = 10) -> String {
        if name.count <= maxChars { return name }
        return String(name.prefix(maxChars - 1)) + "…"
    }

    // MARK: - Attributed Title

    private static func attributedTitle(for record: UsageRecord) -> NSAttributedString {
        let relativeTime = relativeFormatter.localizedString(for: record.lastActivatedAt, relativeTo: Date())
        let duration = formatDuration(record.totalActiveSeconds)
        let traffic = formatBytes(record.totalBytes)
        let countStr = "×\(record.activationCount)"

        // Use tab stops for column alignment
        let tab1: CGFloat = 140  // after app name → count column
        let tab2: CGFloat = 200  // after count → duration column
        let tab3: CGFloat = 270  // after duration → traffic column
        let tab4: CGFloat = 340  // after traffic → relative time column

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .right, location: tab1),
            NSTextTab(textAlignment: .right, location: tab2),
            NSTextTab(textAlignment: .right, location: tab3),
            NSTextTab(textAlignment: .right, location: tab4),
        ]

        let nameFont = NSFont.menuFont(ofSize: 13)
        let statsFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let dimColor = NSColor.secondaryLabelColor

        let result = NSMutableAttributedString()

        // App name (truncated to keep columns aligned)
        result.append(NSAttributedString(string: truncateName(record.displayName), attributes: [
            .font: nameFont,
            .paragraphStyle: paragraphStyle,
        ]))

        // Tab + count
        result.append(NSAttributedString(string: "\t\(countStr)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        // Tab + duration
        result.append(NSAttributedString(string: "\t\(duration)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        // Tab + traffic
        result.append(NSAttributedString(string: "\t\(traffic)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        // Tab + relative time
        result.append(NSAttributedString(string: "\t\(relativeTime)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        return result
    }

    // MARK: - Duration Formatting

    /// Formats seconds into a human-readable duration string.
    /// e.g. 3661 → "1h 1m", 45 → "<1m", 7200 → "2h 0m"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 { return "⏱<1m" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "⏱\(hours)h\(minutes)m"
        }
        return "⏱\(minutes)m"
    }

    // MARK: - Traffic Formatting

    /// Formats bytes into a human-readable string with adaptive units.
    /// e.g. 512 → "512B", 1536 → "1.5KB", 2097152 → "2.0MB"
    static func formatBytes(_ bytes: Int64) -> String {
        let absBytes = Double(bytes)
        if absBytes < 1024 { return "\(bytes)B" }
        if absBytes < 1024 * 1024 { return String(format: "%.1fKB", absBytes / 1024) }
        if absBytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", absBytes / (1024 * 1024)) }
        return String(format: "%.2fGB", absBytes / (1024 * 1024 * 1024))
    }
}
