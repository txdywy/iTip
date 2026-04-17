import Cocoa

final class ActivationMonitor {

    private let store: UsageStoreProtocol
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private let selfBundleIdentifier: String
    private let networkMonitor: NetworkMonitor?

    private var observer: NSObjectProtocol?

    /// Tracks the currently active (foreground) app for duration calculation.
    private var currentForegroundBundleID: String?
    private var foregroundSince: Date?

    /// Indicates whether activation monitoring is currently active.
    private(set) var isMonitoring: Bool = false

    init(store: UsageStoreProtocol,
         notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         dateProvider: @escaping () -> Date = Date.init,
         selfBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
         networkMonitor: NetworkMonitor? = nil) {
        self.store = store
        self.notificationCenter = notificationCenter
        self.dateProvider = dateProvider
        self.selfBundleIdentifier = selfBundleIdentifier
        self.networkMonitor = networkMonitor
    }

    func startMonitoring() {
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }
        isMonitoring = (observer != nil)
    }

    func stopMonitoring() {
        if let observer = observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        isMonitoring = false
    }

    func recordActivation(bundleIdentifier: String, displayName: String) {
        // Filter out self
        guard bundleIdentifier != selfBundleIdentifier else { return }

        do {
            var records = try store.load()
            let now = dateProvider()

            // Read latest accumulated network traffic (non-blocking, background-updated)
            let allTraffic = networkMonitor?.allAccumulatedBytes() ?? [:]

            // Update network bytes for every known record
            for i in records.indices {
                if let bytes = allTraffic[records[i].bundleIdentifier] {
                    let existing = records[i]
                    records[i] = UsageRecord(
                        bundleIdentifier: existing.bundleIdentifier,
                        displayName: existing.displayName,
                        lastActivatedAt: existing.lastActivatedAt,
                        activationCount: existing.activationCount,
                        totalActiveSeconds: existing.totalActiveSeconds,
                        totalBytes: bytes
                    )
                }
            }

            // Accumulate foreground duration for the previously active app
            if let prevID = currentForegroundBundleID,
               let since = foregroundSince,
               prevID != selfBundleIdentifier {
                let duration = now.timeIntervalSince(since)
                if duration > 0,
                   let idx = records.firstIndex(where: { $0.bundleIdentifier == prevID }) {
                    let prev = records[idx]
                    records[idx] = UsageRecord(
                        bundleIdentifier: prev.bundleIdentifier,
                        displayName: prev.displayName,
                        lastActivatedAt: prev.lastActivatedAt,
                        activationCount: prev.activationCount,
                        totalActiveSeconds: prev.totalActiveSeconds + duration,
                        totalBytes: prev.totalBytes
                    )
                }
            }

            // Update foreground tracking to the new app
            currentForegroundBundleID = bundleIdentifier
            foregroundSince = now

            if let index = records.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
                let existing = records[index]
                let updated = UsageRecord(
                    bundleIdentifier: existing.bundleIdentifier,
                    displayName: displayName,
                    lastActivatedAt: now,
                    activationCount: existing.activationCount + 1,
                    totalActiveSeconds: existing.totalActiveSeconds,
                    totalBytes: allTraffic[bundleIdentifier] ?? existing.totalBytes
                )
                records[index] = updated
            } else {
                let newRecord = UsageRecord(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    lastActivatedAt: now,
                    activationCount: 1,
                    totalBytes: allTraffic[bundleIdentifier] ?? 0
                )
                records.append(newRecord)
            }

            try store.save(records)
        } catch {
            // Gracefully handle store errors without crashing
        }
    }

    // MARK: - Private

    private func handleActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        guard let bundleIdentifier = app.bundleIdentifier else {
            return
        }

        let displayName = app.localizedName ?? bundleIdentifier

        recordActivation(bundleIdentifier: bundleIdentifier, displayName: displayName)
    }
}
