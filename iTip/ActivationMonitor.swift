import Cocoa

final class ActivationMonitor {

    private let store: UsageStoreProtocol
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private let selfBundleIdentifier: String

    private var observer: NSObjectProtocol?

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

            if let index = records.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
                let existing = records[index]
                let updated = UsageRecord(
                    bundleIdentifier: existing.bundleIdentifier,
                    displayName: displayName,
                    lastActivatedAt: now,
                    activationCount: existing.activationCount + 1
                )
                records[index] = updated
            } else {
                let newRecord = UsageRecord(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    lastActivatedAt: now,
                    activationCount: 1
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
