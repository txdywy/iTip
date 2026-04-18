import AppKit

final class MenuPresenter {
    private let store: UsageStoreProtocol
    private let ranker: UsageRanker
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Cache app icons to avoid repeated disk lookups.
    private var iconCache: [String: NSImage] = [:]
    /// Cache app URL resolution results.
    private var urlCache: [String: URL?] = [:]

    /// Target for app menu item click actions (typically the AppDelegate).
    weak var menuItemTarget: AnyObject?
    /// Selector invoked when an app menu item is clicked.
    var menuItemAction: Selector?

    /// Closure that returns whether activation monitoring is currently active.
    /// When this returns `false`, a permission warning is shown in the menu.
    var isMonitoringAvailable: () -> Bool = { true }

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
            let appURL: URL?
            if let cached = urlCache[record.bundleIdentifier] {
                appURL = cached
            } else {
                appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleIdentifier)
                urlCache[record.bundleIdentifier] = appURL
            }

            if appURL != nil {
                validRecords.append(record)
            } else {
                removedIdentifiers.insert(record.bundleIdentifier)
            }
        }

        // Clean unresolvable records from the store (async to avoid blocking menu)
        if !removedIdentifiers.isEmpty {
            let cleaned = records.filter { !removedIdentifiers.contains($0.bundleIdentifier) }
            DispatchQueue.global(qos: .utility).async { [store] in
                try? store.save(cleaned)
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
        if let cached = iconCache[bundleIdentifier] {
            return cached
        }
        guard let appURL = urlCache[bundleIdentifier] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        iconCache[bundleIdentifier] = icon
        return icon
    }

    // MARK: - Attributed Title

    private static func attributedTitle(for record: UsageRecord) -> NSAttributedString {
        let relativeTime = relativeFormatter.localizedString(for: record.lastActivatedAt, relativeTo: Date())
        let duration = formatDuration(record.totalActiveSeconds)
        let countStr = "×\(record.activationCount)"
        let dlStr = "↓\(formatBytes(record.totalBytesDownloaded))"

        let tab1: CGFloat = 160
        let tab2: CGFloat = 220
        let tab3: CGFloat = 290
        let tab4: CGFloat = 360

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

        result.append(NSAttributedString(string: record.displayName, attributes: [
            .font: nameFont,
            .paragraphStyle: paragraphStyle,
        ]))

        result.append(NSAttributedString(string: "\t\(countStr)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        result.append(NSAttributedString(string: "\t\(duration)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        result.append(NSAttributedString(string: "\t\(dlStr)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        result.append(NSAttributedString(string: "\t\(relativeTime)", attributes: [
            .font: statsFont,
            .foregroundColor: dimColor,
            .paragraphStyle: paragraphStyle,
        ]))

        return result
    }

    // MARK: - Duration Formatting

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

    /// Format bytes into human-readable string: B, KB, MB, GB.
    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0fKB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1fMB", mb) }
        let gb = mb / 1024
        return String(format: "%.2fGB", gb)
    }
}
