# macOS Menu Bar Recent Apps App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that records app activations, ranks them by recent usage, and lets the user relaunch or activate an app with one click from the menu bar.

**Architecture:** Start with a thin macOS app shell, then add three isolated pieces: a persistent usage store, a ranking service, and a menu bar UI that reads from the store and triggers app activation. Keep event capture, persistence, and presentation separate so the ranking logic can be tested without UI code.

**Tech Stack:** Swift, AppKit, Foundation, XCTest, macOS menu bar APIs.

---

### Task 1: Create the macOS app skeleton and menu bar entry point

**Files:**
- Create: `iTipApp.swift`
- Create: `AppDelegate.swift`
- Create: `MenuBarController.swift`
- Create: `Info.plist`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class AppBootstrapTests: XCTestCase {
    func test_menuBarControllerExists() {
        _ = MenuBarController()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL because the app target and `MenuBarController` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import AppKit

final class MenuBarController {
    init() {}
}
```

```swift
import AppKit

@main
final class iTipApp: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add iTipApp.swift AppDelegate.swift MenuBarController.swift Info.plist tests/AppBootstrapTests.swift
git commit -m "feat: add menu bar app skeleton"
```

### Task 2: Add persistent app usage storage

**Files:**
- Create: `Sources/UsageHistory/UsageRecord.swift`
- Create: `Sources/UsageHistory/UsageStore.swift`
- Create: `Tests/UsageHistoryTests/UsageStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class UsageStoreTests: XCTestCase {
    func test_storeSavesAndLoadsUsageRecord() throws {
        let store = UsageStore(storageURL: temporaryURL())
        let record = UsageRecord(bundleIdentifier: "com.apple.Safari", displayName: "Safari", lastActivatedAt: Date(timeIntervalSince1970: 10), activationCount: 2)

        try store.save([record])
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(loaded[0].displayName, "Safari")
        XCTAssertEqual(loaded[0].activationCount, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageStoreTests`
Expected: FAIL because `UsageStore` and `UsageRecord` are missing.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct UsageRecord: Codable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let lastActivatedAt: Date
    let activationCount: Int
}
```

```swift
import Foundation

final class UsageStore {
    private let storageURL: URL

    init(storageURL: URL) {
        self.storageURL = storageURL
    }

    func save(_ records: [UsageRecord]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: storageURL, options: .atomic)
    }

    func load() throws -> [UsageRecord] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder().decode([UsageRecord].self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UsageStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageHistory/UsageRecord.swift Sources/UsageHistory/UsageStore.swift Tests/UsageHistoryTests/UsageStoreTests.swift
git commit -m "feat: persist app usage history"
```

### Task 3: Implement the recent-app ranking service

**Files:**
- Create: `Sources/UsageHistory/UsageRanker.swift`
- Create: `Tests/UsageHistoryTests/UsageRankerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class UsageRankerTests: XCTestCase {
    func test_rankerOrdersByRecentActivationThenCount() {
        let now = Date(timeIntervalSince1970: 100)
        let records = [
            UsageRecord(bundleIdentifier: "a", displayName: "A", lastActivatedAt: Date(timeIntervalSince1970: 90), activationCount: 1),
            UsageRecord(bundleIdentifier: "b", displayName: "B", lastActivatedAt: Date(timeIntervalSince1970: 95), activationCount: 1),
            UsageRecord(bundleIdentifier: "c", displayName: "C", lastActivatedAt: Date(timeIntervalSince1970: 95), activationCount: 3)
        ]

        let ranked = UsageRanker().rank(records, now: now)

        XCTAssertEqual(ranked.map(\ .bundleIdentifier), ["c", "b", "a"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageRankerTests`
Expected: FAIL because `UsageRanker` is missing.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct UsageRanker {
    func rank(_ records: [UsageRecord], now: Date) -> [UsageRecord] {
        records.sorted {
            if $0.lastActivatedAt != $1.lastActivatedAt {
                return $0.lastActivatedAt > $1.lastActivatedAt
            }
            return $0.activationCount > $1.activationCount
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UsageRankerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageHistory/UsageRanker.swift Tests/UsageHistoryTests/UsageRankerTests.swift
git commit -m "feat: rank apps by recent usage"
```

### Task 4: Capture app activation events and update the store

**Files:**
- Create: `Sources/UsageCapture/AppActivationMonitor.swift`
- Modify: `MenuBarController.swift`
- Create: `Tests/UsageCaptureTests/AppActivationMonitorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class AppActivationMonitorTests: XCTestCase {
    func test_monitorUpdatesExistingRecord() throws {
        let store = InMemoryUsageStore(records: [UsageRecord(bundleIdentifier: "com.apple.Safari", displayName: "Safari", lastActivatedAt: Date(timeIntervalSince1970: 1), activationCount: 1)])
        let monitor = AppActivationMonitor(store: store, dateProvider: { Date(timeIntervalSince1970: 10) })

        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        XCTAssertEqual(store.records[0].activationCount, 2)
        XCTAssertEqual(store.records[0].lastActivatedAt, Date(timeIntervalSince1970: 10))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppActivationMonitorTests`
Expected: FAIL because `AppActivationMonitor` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

final class AppActivationMonitor {
    private let store: UsageStoreProtocol
    private let dateProvider: () -> Date

    init(store: UsageStoreProtocol, dateProvider: @escaping () -> Date = Date.init) {
        self.store = store
        self.dateProvider = dateProvider
    }

    func recordActivation(bundleIdentifier: String, displayName: String) {
        var records = (try? store.load()) ?? []
        if let index = records.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            records[index] = UsageRecord(bundleIdentifier: bundleIdentifier, displayName: displayName, lastActivatedAt: dateProvider(), activationCount: records[index].activationCount + 1)
        } else {
            records.append(UsageRecord(bundleIdentifier: bundleIdentifier, displayName: displayName, lastActivatedAt: dateProvider(), activationCount: 1))
        }
        try? store.save(records)
    }
}
```

```swift
protocol UsageStoreProtocol {
    func save(_ records: [UsageRecord]) throws
    func load() throws -> [UsageRecord]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppActivationMonitorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCapture/AppActivationMonitor.swift MenuBarController.swift Tests/UsageCaptureTests/AppActivationMonitorTests.swift
git commit -m "feat: record app activation events"
```

### Task 5: Build the menu list and one-click activation flow

**Files:**
- Create: `Sources/MenuBar/MenuItemProvider.swift`
- Create: `Sources/MenuBar/AppLauncher.swift`
- Modify: `MenuBarController.swift`
- Create: `Tests/MenuBarTests/MenuItemProviderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class MenuItemProviderTests: XCTestCase {
    func test_providerLimitsItemsToTopTen() {
        let records = (0..<12).map { index in
            UsageRecord(bundleIdentifier: "app\(index)", displayName: "App \(index)", lastActivatedAt: Date(timeIntervalSince1970: TimeInterval(index)), activationCount: index)
        }

        let items = MenuItemProvider().items(from: records)

        XCTAssertEqual(items.count, 10)
        XCTAssertEqual(items.first?.bundleIdentifier, "app11")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuItemProviderTests`
Expected: FAIL because `MenuItemProvider` is missing.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct MenuItemViewModel: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

struct MenuItemProvider {
    private let ranker = UsageRanker()

    func items(from records: [UsageRecord]) -> [MenuItemViewModel] {
        ranker.rank(records, now: Date())
            .prefix(10)
            .map { MenuItemViewModel(bundleIdentifier: $0.bundleIdentifier, displayName: $0.displayName) }
    }
}
```

```swift
import AppKit

final class AppLauncher {
    func activate(bundleIdentifier: String) {
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuItemProviderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBar/MenuItemProvider.swift Sources/MenuBar/AppLauncher.swift MenuBarController.swift Tests/MenuBarTests/MenuItemProviderTests.swift
git commit -m "feat: show recent apps in menu bar"
```

### Task 6: Wire empty states, missing-app cleanup, and permission messaging

**Files:**
- Modify: `MenuBarController.swift`
- Modify: `Sources/UsageHistory/UsageStore.swift`
- Create: `Tests/MenuBarTests/MenuBarStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class MenuBarStateTests: XCTestCase {
    func test_emptyStateWhenNoHistoryExists() {
        let controller = MenuBarController(store: InMemoryUsageStore(records: []))
        XCTAssertEqual(controller.currentTitle(), "No recent apps")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuBarStateTests`
Expected: FAIL because `currentTitle()` is missing.

- [ ] **Step 3: Write minimal implementation**

```swift
final class MenuBarController {
    private let store: UsageStoreProtocol

    init(store: UsageStoreProtocol = FileUsageStore()) {
        self.store = store
    }

    func currentTitle() -> String {
        let records = (try? store.load()) ?? []
        return records.isEmpty ? "No recent apps" : "Recent Apps"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuBarStateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MenuBarController.swift Sources/UsageHistory/UsageStore.swift Tests/MenuBarTests/MenuBarStateTests.swift
git commit -m "feat: handle empty and missing app states"
```

### Task 7: Add integration checks for the end-to-end flow

**Files:**
- Create: `Tests/IntegrationTests/RecentAppsFlowTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import iTip

final class RecentAppsFlowTests: XCTestCase {
    func test_endToEndRankingAndActivationFlow() throws {
        let store = InMemoryUsageStore(records: [])
        let monitor = AppActivationMonitor(store: store, dateProvider: { Date(timeIntervalSince1970: 20) })
        monitor.recordActivation(bundleIdentifier: "com.apple.Safari", displayName: "Safari")

        let items = MenuItemProvider().items(from: try store.load())
        XCTAssertEqual(items.first?.bundleIdentifier, "com.apple.Safari")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RecentAppsFlowTests`
Expected: FAIL if any piece of the flow is still disconnected.

- [ ] **Step 3: Write minimal implementation**

No new production code should be needed if previous tasks are complete; fix any gaps discovered by the integration test.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RecentAppsFlowTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/IntegrationTests/RecentAppsFlowTests.swift
git commit -m "test: cover recent apps flow end to end"
```

### Task 8: Verify the app on macOS and document the launch steps

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run the app locally**

Run: `swift run`
Expected: A macOS menu bar item appears and opens the recent-app list.

- [ ] **Step 2: Manually verify the golden path**
- Click the menu bar item.
- Confirm the recent apps list appears.
- Click an app that is currently running.
- Confirm it is activated.
- Open an app, switch to it, and confirm it moves near the top of the list.

- [ ] **Step 3: Update the README with launch instructions**

```md
## Run locally

1. Open the project in Xcode or run `swift run` from the repository root.
2. Allow the app to run as a menu bar app.
3. Click the menu bar icon to see your recent apps.
```

- [ ] **Step 4: Re-run app checks**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add local run instructions"
```

## Coverage check
- **Menu bar item / popup list / click-to-activate**: Tasks 1, 5, 8
- **Persistent history across restarts**: Task 2
- **Simple ranking based on recent usage plus usage count**: Task 3
- **Capture activation events**: Task 4
- **Top 10 limit**: Task 5
- **Empty state and missing-app handling**: Task 6
- **End-to-end confidence**: Task 7

## Notes for implementers
- Keep `UsageRecord`, `UsageStore`, and `UsageRanker` free of AppKit so they remain unit-testable.
- Avoid adding settings, search, or extra UI until the golden path is working.
- If the repo ends up using Swift Package Manager instead of an Xcode project, map the same file responsibilities into `Sources/` and `Tests/` while keeping the task boundaries intact.
