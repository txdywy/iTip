import AppKit
import os

/// Wraps an optional URL for storage in NSCache.
private final class CachedURL {
    let url: URL?
    init(_ url: URL?) { self.url = url }
}

final class MenuPresenter {
    private let store: UsageStoreProtocol
    private let ranker: UsageRanker
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // Shared tab stop positions for header and data rows
    private static let col1: CGFloat = 150  // Count
    private static let col2: CGFloat = 210  // Time
    private static let col3: CGFloat = 280  // Mem
    private static let col4: CGFloat = 360  // Traffic
    private static let col5: CGFloat = 440  // Last

    /// Lazily-created shared paragraph style (identical for every row).
    private static let paragraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.tabStops = [
            NSTextTab(textAlignment: .right, location: col1),
            NSTextTab(textAlignment: .right, location: col2),
            NSTextTab(textAlignment: .right, location: col3),
            NSTextTab(textAlignment: .right, location: col4),
            NSTextTab(textAlignment: .right, location: col5),
        ]
        return ps
    }()

    /// Cache app icons to avoid repeated disk lookups.
    /// Uses NSCache for automatic memory-pressure eviction instead of
    /// the previous dictionary + manual removeAll strategy.
    private let iconCache = NSCache<NSString, NSImage>()
    /// Cache app URL resolution results.
    private let urlCache = NSCache<NSString, CachedURL>()

    /// Cached records to avoid hitting the store on every menu open.
    /// Uses OSAllocatedUnfairLock for safe, ergonomic locking with
    /// built-in withLock() — replaces manual NSLock lock/unlock.
    private let recordsCache: OSAllocatedUnfairLock<[UsageRecord]?>
    /// Observer for store-change notifications.
    private var storeObserver: NSObjectProtocol?

    /// Target for app menu item click actions (typically the AppDelegate).
    weak var menuItemTarget: AnyObject?
    /// Selector invoked when an app menu item is clicked.
    var menuItemAction: Selector?

    /// Closure that returns whether activation monitoring is currently active.
    var isMonitoringAvailable: () -> Bool = { true }

    init(store: UsageStoreProtocol, ranker: UsageRanker = UsageRanker()) {
        self.store = store
        self.ranker = ranker
        self.recordsCache = OSAllocatedUnfairLock(initialState: nil)

        iconCache.countLimit = 50
        urlCache.countLimit = 50

        // Invalidate cache whenever the store is updated (e.g. by ActivationMonitor or NetworkTracker)
        storeObserver = NotificationCenter.default.addObserver(
            forName: .usageStoreDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.recordsCache.withLock { $0 = nil }
        }
    }

    deinit {
        if let observer = storeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func buildMenu() -> NSMenu {
        dispatchPrecondition(condition: .onQueue(.main))
        let menu = NSMenu()

        if !isMonitoringAvailable() {
            let warningItem = NSMenuItem(title: "⚠ Monitoring unavailable — check permissions", action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Use cached records if available, otherwise load from store
        let records: [UsageRecord]
        let cached: [UsageRecord]? = recordsCache.withLock { $0 }
        if let cached {
            records = cached
        } else {
            let loaded = (try? store.load()) ?? []
            recordsCache.withLock { $0 = loaded }
            records = loaded
        }

        let ranked = ranker.rank(records)

        var validRecords: [UsageRecord] = []
        var removedIdentifiers: Set<String> = []

        for record in ranked {
            let appURL: URL?
            let cacheKey = record.bundleIdentifier as NSString
            if let cached = urlCache.object(forKey: cacheKey) {
                appURL = cached.url
            } else {
                appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleIdentifier)
                urlCache.setObject(CachedURL(appURL), forKey: cacheKey)
            }

            if appURL != nil {
                validRecords.append(record)
            } else {
                removedIdentifiers.insert(record.bundleIdentifier)
            }
        }

        if !removedIdentifiers.isEmpty {
            let cleaned = records.filter { !removedIdentifiers.contains($0.bundleIdentifier) }
            recordsCache.withLock { $0 = cleaned }
            DispatchQueue.global(qos: .utility).async { [store] in
                try? store.save(cleaned)
            }
        }

        if validRecords.isEmpty {
            let noAppsItem = NSMenuItem(title: "No recent apps", action: nil, keyEquivalent: "")
            noAppsItem.isEnabled = false
            menu.addItem(noAppsItem)
        } else {
            // Header row with placeholder icon for alignment
            let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            header.attributedTitle = MenuPresenter.headerTitle()
            header.isEnabled = false
            // Use a transparent 16x16 image to match data row icon indent
            let placeholder = NSImage(size: NSSize(width: 16, height: 16))
            header.image = placeholder
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())

            for record in validRecords {
                let item = NSMenuItem(title: "", action: menuItemAction, keyEquivalent: "")
                item.target = menuItemTarget
                item.representedObject = record.bundleIdentifier
                item.attributedTitle = MenuPresenter.attributedTitle(for: record)
                item.image = cachedIcon(for: record.bundleIdentifier)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit iTip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Icon Cache

    private func cachedIcon(for bundleIdentifier: String) -> NSImage? {
        let cacheKey = bundleIdentifier as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }
        let resolvedURL: URL?
        if let cached = urlCache.object(forKey: cacheKey) {
            resolvedURL = cached.url
        } else {
            resolvedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        guard let appURL = resolvedURL else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        iconCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    // MARK: - Header

    private static func headerTitle() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let color = NSColor.tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "App", attributes: attrs))
        result.append(NSAttributedString(string: "\tCount", attributes: attrs))
        result.append(NSAttributedString(string: "\tTime", attributes: attrs))
        result.append(NSAttributedString(string: "\tMem", attributes: attrs))
        result.append(NSAttributedString(string: "\tTraffic", attributes: attrs))
        result.append(NSAttributedString(string: "\tLast", attributes: attrs))
        return result
    }

    // MARK: - Data Row

    private static func attributedTitle(for record: UsageRecord) -> NSAttributedString {
        let relativeTime = relativeFormatter.localizedString(for: record.lastActivatedAt, relativeTo: Date())
        let duration = formatDuration(record.totalActiveSeconds)
        let countStr = "×\(record.activationCount)"
        let memStr = formatMemory(record.residentMemoryBytes)
        let dlStr = "↓\(formatBytes(record.totalBytesDownloaded))"

        let nameFont = NSFont.menuFont(ofSize: 13)
        let statsFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let dimColor = NSColor.secondaryLabelColor

        // Shared attributes for all stats columns — avoids recreating
        // identical dictionary 5 times per row.
        let statsAttrs: [NSAttributedString.Key: Any] = [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]

        let result = NSMutableAttributedString()

        result.append(NSAttributedString(string: record.displayName, attributes: [
            .font: nameFont,
            .paragraphStyle: paragraphStyle,
        ]))

        result.append(NSAttributedString(string: "\t\(countStr)", attributes: statsAttrs))
        result.append(NSAttributedString(string: "\t\(duration)", attributes: statsAttrs))
        result.append(NSAttributedString(string: "\t\(memStr)", attributes: statsAttrs))
        result.append(NSAttributedString(string: "\t\(dlStr)", attributes: statsAttrs))
        result.append(NSAttributedString(string: "\t\(relativeTime)", attributes: statsAttrs))

        return result
    }

    // MARK: - Formatting

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

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1fKB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1fMB", mb) }
        let gb = mb / 1024
        return String(format: "%.2fGB", gb)
    }

    static func formatMemory(_ bytes: Int64) -> String {
        if bytes <= 0 { return "—" }
        let mb = Double(bytes) / (1024 * 1024)
        if mb < 1 { return "<1M" }
        if mb < 1024 { return String(format: "%.0fM", mb) }
        let gb = mb / 1024
        return String(format: "%.1fG", gb)
    }
}
