import Cocoa

final class ActivationMonitor {

    private let store: UsageStoreProtocol
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private let selfBundleIdentifier: String

    private var observer: NSObjectProtocol?

    /// In-memory cache of records to avoid disk I/O on every activation.
    private var cachedRecords: [UsageRecord]?
    /// Timer to debounce disk writes.
    private var saveTimer: Timer?
    /// Whether the cache has unsaved changes.
    private var isDirty = false

    /// Tracks the currently active (foreground) app for duration calculation.
    private var currentForegroundBundleID: String?
    private var foregroundSince: Date?

    /// Indicates whether activation monitoring is currently active.
    private(set) var isMonitoring: Bool = false

    init(store: UsageStoreProtocol,
         notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         dateProvider: @escaping () -> Date = Date.init,
         selfBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "") {
        self.store = store
        self.notificationCenter = notificationCenter
        self.dateProvider = dateProvider
        self.selfBundleIdentifier = selfBundleIdentifier
    }

    func startMonitoring() {
        // Load records into memory cache once
        cachedRecords = (try? store.load()) ?? []

        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }
        isMonitoring = (observer != nil)

        // Periodic save every 5 seconds if dirty
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.flushIfDirty()
        }
    }

    func stopMonitoring() {
        if let observer = observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        saveTimer?.invalidate()
        saveTimer = nil
        flushIfDirty()
        isMonitoring = false
    }

    func recordActivation(bundleIdentifier: String, displayName: String) {
        guard bundleIdentifier != selfBundleIdentifier else { return }

        if cachedRecords == nil {
            cachedRecords = (try? store.load()) ?? []
        }

        var records = cachedRecords!
        let now = dateProvider()

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
                    totalActiveSeconds: prev.totalActiveSeconds + duration
                )
            }
        }

        // Update foreground tracking
        currentForegroundBundleID = bundleIdentifier
        foregroundSince = now

        if let index = records.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            let existing = records[index]
            records[index] = UsageRecord(
                bundleIdentifier: existing.bundleIdentifier,
                displayName: displayName,
                lastActivatedAt: now,
                activationCount: existing.activationCount + 1,
                totalActiveSeconds: existing.totalActiveSeconds
            )
        } else {
            records.append(UsageRecord(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                lastActivatedAt: now,
                activationCount: 1
            ))
        }

        cachedRecords = records
        isDirty = true
    }

    // MARK: - Private

    private func flushIfDirty() {
        guard isDirty, let records = cachedRecords else { return }
        isDirty = false
        try? store.save(records)
    }

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
