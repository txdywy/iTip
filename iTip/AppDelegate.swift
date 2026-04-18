import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusBarController: StatusBarController?
    private var activationMonitor: ActivationMonitor?
    private var networkTracker: NetworkTracker?
    private var memorySampler: MemorySampler?
    private let appLauncher = AppLauncher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore()
        let ranker = UsageRanker()

        activationMonitor = ActivationMonitor(store: store)
        activationMonitor?.startMonitoring()

        networkTracker = NetworkTracker(store: store)
        networkTracker?.start(interval: 10.0)

        memorySampler = MemorySampler(store: store)
        memorySampler?.start(interval: 10.0)

        let menuPresenter = MenuPresenter(store: store, ranker: ranker)
        menuPresenter.menuItemTarget = self
        menuPresenter.menuItemAction = #selector(launchApp(_:))
        menuPresenter.isMonitoringAvailable = { [weak self] in
            self?.activationMonitor?.isMonitoring ?? false
        }

        statusBarController = StatusBarController(menuPresenter: menuPresenter)

        // Seed store with Spotlight data on cold start (empty store)
        // Done async after UI is ready to avoid blocking app launch
        DispatchQueue.global(qos: .utility).async {
            let seeder = SpotlightSeeder(store: store)
            seeder.seedIfEmpty()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        activationMonitor?.stopMonitoring()
        networkTracker?.stop()
        memorySampler?.stop()
    }

    // MARK: - Menu Item Actions

    @objc func launchApp(_ sender: NSMenuItem) {
        guard let bundleIdentifier = sender.representedObject as? String else { return }

        appLauncher.activate(bundleIdentifier: bundleIdentifier) { [weak self] result in
            switch result {
            case .success:
                break
            case .failure(let error):
                self?.showErrorAlert(for: error)
            }
        }
    }

    // MARK: - Private

    private func showErrorAlert(for error: AppLaunchError) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch error {
        case .applicationNotFound(let bundleIdentifier):
            alert.messageText = "Application Not Found"
            alert.informativeText = "The application \"\(bundleIdentifier)\" could not be found on this system."
        case .launchFailed(let bundleIdentifier, let underlyingError):
            alert.messageText = "Launch Failed"
            alert.informativeText = "Failed to launch \"\(bundleIdentifier)\": \(underlyingError.localizedDescription)"
        }

        alert.addButton(withTitle: "OK")

        // Non-blocking: attach to key window if available, otherwise show as floating panel
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
