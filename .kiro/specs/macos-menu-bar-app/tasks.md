# Implementation Plan: iTip macOS Menu Bar App

## Overview

Build a macOS menu bar app that records app activations, ranks them by recent usage, and lets the user relaunch or activate an app with one click. Implementation follows the approved design's layered architecture: UsageRecord data model → UsageStore persistence → UsageRanker ranking engine → ActivationMonitor event capture → MenuPresenter UI → AppLauncher activation → wiring and integration. The existing code skeleton (AppDelegate, StatusBarController, main.swift) is extended incrementally. SwiftCheck is added as a test dependency for property-based tests.

## Tasks

- [x] 1. Set up project foundations and core data model
  - [x] 1.1 Create `UsageRecord` struct with Codable and Equatable conformance
    - Create `iTip/UsageRecord.swift`
    - Define `bundleIdentifier: String`, `displayName: String`, `lastActivatedAt: Date`, `activationCount: Int`
    - _Requirements: 9.1, 9.2_

  - [x] 1.2 Create `UsageStoreProtocol` and file-based `UsageStore` implementation
    - Create `iTip/UsageStoreProtocol.swift` with `load() throws -> [UsageRecord]` and `save(_ records: [UsageRecord]) throws`
    - Create `iTip/UsageStore.swift` implementing `UsageStoreProtocol`
    - Use `JSONEncoder`/`JSONDecoder` for serialization
    - Use `Data.WritingOptions.atomic` for safe writes
    - Default storage path: `~/Library/Application Support/iTip/usage.json`
    - Auto-create storage directory on first write
    - Return empty array when file does not exist
    - Return empty array and log via `os_log` when JSON is corrupted
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 8.3, 9.1, 9.2_

  - [x] 1.3 Create `InMemoryUsageStore` test helper conforming to `UsageStoreProtocol`
    - Create `iTipTests/InMemoryUsageStore.swift`
    - Store records in an in-memory array for test injection
    - _Requirements: 3.1 (test support)_

  - [x] 1.4 Write unit tests for `UsageStore`
    - Test load returns empty array when file does not exist
    - Test save then load round-trip with valid records
    - Test load returns empty array when file contains corrupted JSON
    - Test atomic write does not corrupt existing data
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 1.5 Write property test for UsageRecord serialization round-trip
    - **Property 1: UsageRecord 序列化 round-trip**
    - Use SwiftCheck to generate random `[UsageRecord]` lists (random strings, dates, positive integers)
    - Verify `JSONEncoder` → `JSONDecoder` produces equivalent list
    - Minimum 100 iterations
    - **Validates: Requirements 3.1, 3.3, 9.1, 9.2, 9.3**

- [x] 2. Implement ranking engine
  - [x] 2.1 Create `UsageRanker` struct
    - Create `iTip/UsageRanker.swift`
    - Implement `func rank(_ records: [UsageRecord]) -> [UsageRecord]`
    - Primary sort: `lastActivatedAt` descending
    - Secondary sort: `activationCount` descending
    - Limit output to top 10 entries
    - Keep free of AppKit imports
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 2.2 Write property test for ranking sort correctness
    - **Property 4: Ranking 排序正确性**
    - Generate random `[UsageRecord]` lists including records with equal timestamps
    - Verify output is sorted by `lastActivatedAt` descending, then `activationCount` descending
    - **Validates: Requirements 4.1, 4.2**

  - [x] 2.3 Write property test for ranking idempotency
    - **Property 5: Ranking 幂等性**
    - Generate random `[UsageRecord]` lists
    - Verify `rank(records) == rank(rank(records))`
    - **Validates: Requirements 4.3**

  - [x] 2.4 Write property test for ranking output count limit
    - **Property 6: Ranking 输出数量限制**
    - Generate random `[UsageRecord]` lists of size 0–20
    - Verify output length equals `min(N, 10)`
    - **Validates: Requirements 4.4**

  - [x] 2.5 Write unit tests for `UsageRanker`
    - Test empty input returns empty output
    - Test list with fewer than 10 items returns all items sorted
    - Test list with more than 10 items returns exactly 10
    - Test secondary sort by activation count when timestamps are equal
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [x] 3. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement activation event capture
  - [x] 4.1 Create `ActivationMonitor` class
    - Create `iTip/ActivationMonitor.swift`
    - Accept `UsageStoreProtocol`, `NotificationCenter`, `dateProvider: () -> Date`, `selfBundleIdentifier: String` via init
    - Implement `startMonitoring()` to observe `NSWorkspace.didActivateApplicationNotification`
    - Implement `stopMonitoring()` to remove observer
    - Implement `recordActivation(bundleIdentifier:displayName:)` to update or create records in the store
    - Filter out activations where `bundleIdentifier == selfBundleIdentifier`
    - Ignore events missing `bundleIdentifier`; use `bundleIdentifier` as fallback when `localizedName` is missing
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 4.2 Write property test for recordActivation updating existing records
    - **Property 2: recordActivation 更新已有记录**
    - Generate random existing `UsageRecord` (activationCount >= 1, any timestamp)
    - Call `recordActivation` with matching `bundleIdentifier`
    - Verify `activationCount` incremented by exactly 1 and `lastActivatedAt` updated to injected timestamp
    - **Validates: Requirements 2.3**

  - [x] 4.3 Write property test for recordActivation creating new records
    - **Property 3: recordActivation 创建新记录**
    - Generate random store state and a `bundleIdentifier` not in the store
    - Call `recordActivation` with the new identifier
    - Verify new record has `activationCount == 1` and correct timestamp, and all pre-existing records are unchanged
    - **Validates: Requirements 2.4**

  - [x] 4.4 Write unit tests for `ActivationMonitor`
    - Test self-filtering: activations with `selfBundleIdentifier` are ignored
    - Test missing `bundleIdentifier` events are ignored
    - Test missing `localizedName` falls back to `bundleIdentifier`
    - Test new app creates record with count 1
    - Test existing app increments count by 1
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 5. Implement menu presentation layer
  - [x] 5.1 Create `MenuPresenter` class
    - Create `iTip/MenuPresenter.swift`
    - Accept `UsageStoreProtocol` and `UsageRanker` via init
    - Implement `buildMenu() -> NSMenu`
    - When records exist: up to 10 app entries (icon + display name), separator, "Quit iTip" item
    - When no records: disabled "No recent apps" item, separator, "Quit iTip" item
    - Skip entries whose `bundleIdentifier` cannot be resolved to an installed app (via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`)
    - Remove unresolvable records from the store during menu build
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 7.1, 7.2_

  - [x] 5.2 Write unit tests for `MenuPresenter`
    - Test empty store produces menu with disabled "No recent apps" item and "Quit iTip"
    - Test menu items match ranked order and count
    - Test unresolvable `bundleIdentifier` entries are omitted from menu
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 7.1, 7.2_

- [x] 6. Implement app launcher
  - [x] 6.1 Create `AppLauncher` struct and `AppLaunchError` enum
    - Create `iTip/AppLauncher.swift`
    - Define `AppLaunchError.applicationNotFound(bundleIdentifier:)` and `.launchFailed(bundleIdentifier:underlyingError:)`
    - Implement `func activate(bundleIdentifier: String) -> Result<Void, AppLaunchError>`
    - If app is running: call `NSRunningApplication.activate()`
    - If app is not running: use `NSWorkspace.shared.openApplication(at:configuration:)` to launch
    - If app cannot be found: return `.applicationNotFound`
    - _Requirements: 6.1, 6.2, 6.3_

  - [x] 6.2 Write unit tests for `AppLauncher`
    - Test returns `.applicationNotFound` for unknown `bundleIdentifier`
    - _Requirements: 6.1, 6.2, 6.3_

- [x] 7. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Wire components together and integrate into app lifecycle
  - [x] 8.1 Update `StatusBarController` to integrate `MenuPresenter`
    - Modify `iTip/StatusBarController.swift`
    - Set the `NSStatusItem`'s menu via `MenuPresenter.buildMenu()`
    - Implement `NSMenuDelegate.menuNeedsUpdate(_:)` to rebuild menu on each open (ensures fresh data)
    - _Requirements: 1.4, 5.4_

  - [x] 8.2 Update `AppDelegate` to wire all components
    - Modify `iTip/AppDelegate.swift`
    - Instantiate `UsageStore` with default storage path
    - Instantiate `ActivationMonitor` with the store and start monitoring
    - Instantiate `MenuPresenter` with the store and ranker
    - Pass `MenuPresenter` to `StatusBarController`
    - Wire menu item click actions to `AppLauncher.activate(bundleIdentifier:)`
    - Display error alerts for `AppLaunchError` cases
    - _Requirements: 1.1, 1.2, 1.3, 6.1, 6.2, 6.3, 8.1, 8.2_

  - [x] 8.3 Add permission and error handling UI
    - If activation monitoring fails due to permissions, display a user-facing message in the menu
    - If `AppLauncher` returns an error, show an `NSAlert` with the failure reason
    - Ensure `UsageStore` errors are handled gracefully without crashing
    - _Requirements: 8.1, 8.2, 8.3_

- [x] 9. Add SwiftCheck dependency and configure test target
  - [x] 9.1 Add SwiftCheck as a test dependency
    - Add SwiftCheck package via Xcode project settings or a local `Package.swift` for test dependency resolution
    - Ensure `iTipTests` target can import `SwiftCheck`
    - Create SwiftCheck `Arbitrary` conformance for `UsageRecord` in test target
    - _Requirements: (test infrastructure)_

- [x] 10. Integration tests
  - [x] 10.1 Write integration test for full data flow
    - Test: record activation → store save → load → rank → menu build
    - Use `InMemoryUsageStore` to verify the complete pipeline
    - _Requirements: 2.3, 2.4, 3.1, 4.1, 5.1, 5.4_

  - [x] 10.2 Write integration test for activation → store update → menu refresh
    - Test: activate app → verify store updated → rebuild menu → verify new order
    - _Requirements: 2.3, 5.4_

- [x] 11. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The existing code skeleton (AppDelegate, StatusBarController, main.swift, Info.plist) is extended in-place rather than recreated
- SwiftCheck is used for property-based testing with minimum 100 iterations per property
- `UsageStoreProtocol` enables dependency injection throughout for testability
