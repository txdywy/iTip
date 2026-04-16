# macOS Menu Bar Recent Apps App — Design Spec

## Goal
Build a macOS menu bar app that shows a list of recently used apps and lets the user activate any app from the list with one click.

## Scope
### In scope
- Menu bar item that stays available while the app is running.
- Popup list of recently used apps.
- Click-to-activate behavior for each app in the list.
- Persistent history across app restarts.
- Simple ranking based on recent usage plus usage count.

### Out of scope
- Search box.
- App grouping or filters.
- User-configurable ranking modes.
- Analytics or cloud sync.
- Dock icon–first navigation.

## User experience
1. User clicks the menu bar icon.
2. The app opens a compact list of the most recently used apps.
3. Each row shows the app icon and app name.
4. Clicking a row switches focus to that app.
5. If the app is not currently running, the app is launched first and then activated.

## Ranking model
The first version uses a lightweight ranking model:
- Track the last activation time for each app.
- Track the number of times each app was activated.
- Sort primarily by most recent activation.
- Use activation count as a secondary tie-breaker.
- Limit the visible list to the top 10 apps.

This keeps the behavior easy to understand while still surfacing both very recent apps and apps that are used often.

## Data model
Store one record per app:
- app identifier
- app display name
- app icon reference or resolvable bundle metadata
- last activation timestamp
- activation count

The storage layer must survive app restarts.

## Core components
### 1. App state manager
Responsible for startup, wiring event listeners, and coordinating the menu bar UI with the usage history.

### 2. Usage recorder
Listens for app activation events and updates the persisted history.

### 3. Ranking engine
Turns the stored app history into a sorted list for display.

### 4. Menu presentation and activation handler
Renders the dropdown menu and activates the selected app when the user clicks a row.

## Data flow
1. User activates an app in macOS.
2. The usage recorder receives the activation event.
3. The recorder updates the local history store.
4. The ranking engine recalculates the app order.
5. The menu renders the latest ordered list when opened.
6. The user clicks an entry and the activation handler brings that app to the foreground.

## Edge cases
- **No history yet**: show an empty state message instead of an empty list.
- **Removed app**: omit entries that can no longer be resolved to a real app.
- **App not running**: launch it before activating.
- **Permission limitations**: if macOS prevents activation tracking or app switching, surface a clear user-facing message.
- **Long list**: show only the top 10 items.

## Testing strategy
- Verify activation events update the history record.
- Verify ranking order is stable and deterministic for recent items.
- Verify empty state behavior when no apps have been recorded.
- Verify clicking a menu item triggers the correct activation path.
- Verify removed apps are ignored or cleaned up.

## Acceptance criteria
- The app appears in the macOS menu bar.
- Clicking the menu bar item shows a list of recently used apps.
- The list is ordered by recent usage with activation count as a secondary factor.
- Clicking an app activates it successfully.
- Usage history persists across restarts.
- The UI handles empty and missing-app cases gracefully.
