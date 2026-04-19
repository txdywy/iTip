import Cocoa

final class ActivationMonitor {

    private let store: UsageStoreProtocol
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private let selfBundleIdentifier: String

    /// Serial queue protecting all mutable state from data races.
    private let syncQueue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "iTip").activationMonitor")

    private var observer: NSObjectProtocol?

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
        syncQueue.sync {
            saveTimer?.cancel()
            saveTimer = nil
            if let existing = observer {
                notificationCenter.removeObserver(existing)
                observer = nil
            }

            populateCache()

            observer = notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleActivation(notification)
            }
            isMonitoring = (observer != nil)

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
            if let observer = observer {
                notificationCenter.removeObserver(observer)
                self.observer = nil
            }
            saveTimer?.cancel()
            saveTimer = nil
            _flushIfDirty()
            isMonitoring = false
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

    func recordActivation(bundleIdentifier: String, displayName: String) {
        syncQueue.sync {
            guard bundleIdentifier != selfBundleIdentifier else { return }
            guard !bundleIdentifier.isEmpty else { return }

            ensureCacheInitialized()

            let now = dateProvider()

            // Accumulate foreground duration for the previously active app
            if let prevID = currentForegroundBundleID,
               let since = foregroundSince,
               prevID != selfBundleIdentifier,
               let idx = indexByBundleID[prevID] {
                let duration = now.timeIntervalSince(since)
                if duration > 0 {
                    cachedRecords[idx].totalActiveSeconds += duration
                }
            }

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
    }

    // MARK: - Private

    private func rebuildIndex() {
        indexByBundleID.removeAll(keepingCapacity: true)
        for (i, record) in cachedRecords.enumerated() {
            indexByBundleID[record.bundleIdentifier] = i
        }
    }

    /// Internal flush implementation. Must be called while holding `syncQueue`.
    private func _flushIfDirty() {
        guard isDirty else { return }
        isDirty = false

        let snapshot = cachedRecords
        do {
            try store.updateRecords { diskRecords in
                // Merge: overlay activation data from cache onto disk records,
                // preserving data written by NetworkTracker and MemorySampler.
                var diskRecordIndex: [String: Int] = [:]
                for (i, record) in diskRecords.enumerated() {
                    diskRecordIndex[record.bundleIdentifier] = i
                }

                for var record in snapshot {
                    if let idx = diskRecordIndex[record.bundleIdentifier] {
                        // Preserve network and memory data from disk
                        record.totalBytesDownloaded = diskRecords[idx].totalBytesDownloaded
                        record.residentMemoryBytes = diskRecords[idx].residentMemoryBytes
                        diskRecords[idx] = record
                    } else {
                        diskRecords.append(record)
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
}
