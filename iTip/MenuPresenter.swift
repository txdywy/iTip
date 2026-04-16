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
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleIdentifier) != nil {
                validRecords.append(record)
            } else {
                removedIdentifiers.insert(record.bundleIdentifier)
            }
        }

        // Clean unresolvable records from the store
        if !removedIdentifiers.isEmpty {
            let cleaned = records.filter { !removedIdentifiers.contains($0.bundleIdentifier) }
            try? store.save(cleaned)
        }

        if validRecords.isEmpty {
            let noAppsItem = NSMenuItem(title: "No recent apps", action: nil, keyEquivalent: "")
            noAppsItem.isEnabled = false
            menu.addItem(noAppsItem)
        } else {
            for record in validRecords {
                let relativeTime = MenuPresenter.relativeFormatter.localizedString(for: record.lastActivatedAt, relativeTo: Date())
                let duration = MenuPresenter.formatDuration(record.totalActiveSeconds)
                let title = "\(record.displayName)  ×\(record.activationCount)  \(duration)  \(relativeTime)"
                let item = NSMenuItem(title: title, action: menuItemAction, keyEquivalent: "")
                item.target = menuItemTarget
                item.representedObject = record.bundleIdentifier
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleIdentifier) {
                    item.image = NSWorkspace.shared.icon(forFile: appURL.path)
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

    // MARK: - Private

    /// Formats seconds into a human-readable duration string.
    /// e.g. 3661 → "1h 1m", 45 → "<1m", 7200 → "2h 0m"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 { return "⏱<1m" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "⏱\(hours)h \(minutes)m"
        }
        return "⏱\(minutes)m"
    }
}
