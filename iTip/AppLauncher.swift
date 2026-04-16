import AppKit

enum AppLaunchError: Error {
    case applicationNotFound(bundleIdentifier: String)
    case launchFailed(bundleIdentifier: String, underlyingError: Error)
}

struct AppLauncher {
    /// Activates or launches the app with the given bundle identifier.
    /// Completion is always called on the main thread.
    func activate(bundleIdentifier: String, completion: @escaping (Result<Void, AppLaunchError>) -> Void) {
        // If the app is already running, activate it directly
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if let runningApp = runningApps.first {
            runningApp.activate()
            completion(.success(()))
            return
        }

        // App is not running — try to find and launch it
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            completion(.failure(.applicationNotFound(bundleIdentifier: bundleIdentifier)))
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.launchFailed(bundleIdentifier: bundleIdentifier, underlyingError: error)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}
