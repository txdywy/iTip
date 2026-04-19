import Cocoa

final class ActivationMonitor {

    private let store: UsageStoreProtocol
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private let selfBundleIdentifier: String

    /// Serial queue protecting all mutable state from data races.
    private let syncQueue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "iTip").activationMonitor")

    private var observers: [NSObjectProtocol] = []

    /// In-memory cache of records to avoid disk I/O on every activation.
    private var cachedRecords: [UsageRecord] = []
    /// O(1) lookup index: bundleIdentifier → index in cachedRecords.
    private var indexByBundleID: [String: Int] = [:]
    /// Whether the cache has been populated from the store.
    private var cacheInitialized = false
    /// Periodic flush while dirty (`DispatchSourceTimer` on `syncQueue`; avoids `Timer` + run loop on a GCD worker thread).
    private var saveTimer: DispatchSourceTimer?
    /// Whether the cache has unsaved changes.
    private var isDirty = false

    /// Tracks the currently active (foreground) app for duration calculation.
    private var currentForegroundBundleID: String?
    private var foregroundSince: Date?

    /// Indicates whether activation monitoring is currently active.
    /// Thread-safe: reads go through syncQueue to prevent data races with
    /// writes that happen inside startMonitoring/stopMonitoring.
    private var _isMonitoring: Bool = false
    var isMonitoring: Bool {
        syncQueue.sync { _isMonitoring }
    }

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
        syncQueue.sync {
            saveTimer?.cancel()
            saveTimer = nil
            for obs in observers { notificationCenter.removeObserver(obs) }
            observers.removeAll()

            populateCache()

            observers.append(notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleActivation(notification)
            })
            
            observers.append(notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSleep()
            })

            observers.append(notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleWake()
            })

            _isMonitoring = !observers.isEmpty

            let t = DispatchSource.makeTimerSource(queue: syncQueue)
            t.schedule(deadline: .now() + 5.0, repeating: 5.0)
            t.setEventHandler { [weak self] in
                self?._flushIfDirty()
            }
            t.resume()
            saveTimer = t
        }
    }

    func stopMonitoring() {
        syncQueue.sync {
            for obs in observers { notificationCenter.removeObserver(obs) }
            observers.removeAll()

            saveTimer?.cancel()
            saveTimer = nil
            
            // Capture any accumulated active time before stopping
            _commitCurrentSession(now: dateProvider())
            foregroundSince = nil

            _flushIfDirty()
            _isMonitoring = false
        }
    }

    // MARK: - Cache Management

    /// Persists any unsaved in-memory changes to the store.
    /// Useful for testing or when immediate persistence is needed.
    func flush() {
        syncQueue.sync {
            _flushIfDirty()
        }
    }

    private func populateCache() {
        cachedRecords = (try? store.load()) ?? []
        rebuildIndex()
        cacheInitialized = true
    }

    private func ensureCacheInitialized() {
        guard !cacheInitialized else { return }
        populateCache()
    }

    /// Public entry point: dispatches onto syncQueue and delegates to the
    /// unsynchronized `_recordActivation`. Splitting the logic prevents
    /// accidental nested locking if internal code ever needs to call it.
    func recordActivation(bundleIdentifier: String, displayName: String) {
        syncQueue.sync {
            _recordActivation(bundleIdentifier: bundleIdentifier, displayName: displayName)
        }
    }

    // MARK: - Private

    /// Unsynchronized implementation of recordActivation.
    /// **Must** be called while already on `syncQueue`.
    private func _recordActivation(bundleIdentifier: String, displayName: String) {
        guard bundleIdentifier != selfBundleIdentifier else { return }
        guard !bundleIdentifier.isEmpty else { return }

        ensureCacheInitialized()

        let now = dateProvider()

        _commitCurrentSession(now: now)

        // Update foreground tracking
        currentForegroundBundleID = bundleIdentifier
        foregroundSince = now

        if let idx = indexByBundleID[bundleIdentifier] {
            cachedRecords[idx].lastActivatedAt = now
            cachedRecords[idx].activationCount += 1
            cachedRecords[idx].displayName = displayName
        } else {
            indexByBundleID[bundleIdentifier] = cachedRecords.count
            cachedRecords.append(UsageRecord(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                lastActivatedAt: now,
                activationCount: 1
            ))
        }

        isDirty = true
    }

    private func rebuildIndex() {
        indexByBundleID.removeAll(keepingCapacity: true)
        for (i, record) in cachedRecords.enumerated() {
            indexByBundleID[record.bundleIdentifier] = i
        }
    }

    /// Internal flush implementation. Must be called while holding `syncQueue`.
    ///
    /// Merge strategy: uses disk records as the base and only overlays
    /// activation-specific fields from the in-memory cache. This way, fields
    /// written by other writers (NetworkTracker → totalBytesDownloaded,
    /// MemorySampler → residentMemoryBytes, and any future fields) are
    /// preserved automatically without explicit copy-back logic.
    private func _flushIfDirty() {
        guard isDirty else { return }
        isDirty = false

        let snapshot = cachedRecords
        var snapshotIndex: [String: Int] = [:]
        for (i, record) in snapshot.enumerated() {
            snapshotIndex[record.bundleIdentifier] = i
        }

        do {
            try store.updateRecords { diskRecords in
                var diskRecordIndex: [String: Int] = [:]
                for (i, record) in diskRecords.enumerated() {
                    diskRecordIndex[record.bundleIdentifier] = i
                }

                for cachedRecord in snapshot {
                    if let idx = diskRecordIndex[cachedRecord.bundleIdentifier] {
                        // Overlay only activation-related fields onto the disk
                        // record, preserving network, memory, and any future
                        // fields written by other components.
                        diskRecords[idx].lastActivatedAt = cachedRecord.lastActivatedAt
                        diskRecords[idx].activationCount = cachedRecord.activationCount
                        diskRecords[idx].displayName = cachedRecord.displayName
                        diskRecords[idx].totalActiveSeconds = cachedRecord.totalActiveSeconds
                    } else {
                        diskRecords.append(cachedRecord)
                    }
                }
            }
        } catch {
            // If merge-save fails, mark dirty so we retry next flush
            isDirty = true
        }
    }

    private func handleActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return
        }

        let displayName = app.localizedName ?? bundleIdentifier
        recordActivation(bundleIdentifier: bundleIdentifier, displayName: displayName)
    }

    private func handleSleep() {
        syncQueue.sync {
            _commitCurrentSession(now: dateProvider())
            // Clear tracking so sleep duration is completely ignored
            foregroundSince = nil
            _flushIfDirty() // persist everything securely right before sleep
        }
    }

    private func handleWake() {
        syncQueue.sync {
            // Restore since date so the active app cleanly resumes accumulation.
            foregroundSince = dateProvider()
        }
    }

    private func _commitCurrentSession(now: Date) {
        guard let currentID = currentForegroundBundleID,
              let since = foregroundSince,
              currentID != selfBundleIdentifier,
              let idx = indexByBundleID[currentID] else {
            return
        }
        
        let duration = now.timeIntervalSince(since)
        if duration > 0 {
            cachedRecords[idx].totalActiveSeconds += duration
            isDirty = true
        }
    }
}
