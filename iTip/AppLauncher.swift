import AppKit

enum AppLaunchError: Error {
    case applicationNotFound(bundleIdentifier: String)
    case launchFailed(bundleIdentifier: String, underlyingError: Error)
}

struct AppLauncher {
    func activate(bundleIdentifier: String) -> Result<Void, AppLaunchError> {
        // If the app is already running, activate it directly
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if let runningApp = runningApps.first {
            runningApp.activate()
            return .success(())
        }

        // App is not running — try to find and launch it
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return .failure(.applicationNotFound(bundleIdentifier: bundleIdentifier))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let error = launchError {
            return .failure(.launchFailed(bundleIdentifier: bundleIdentifier, underlyingError: error))
        }

        return .success(())
    }
}
