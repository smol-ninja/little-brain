# Architecture

littlebrain reads chat IDs and titles from Codex's local SQLite database. It follows those IDs over Codex's local socket to receive running and unread status. SQLite does not supply live status.

## Usage

```swift
let monitor = PulseMonitor(configuration: .localDefault)
monitor.start()
// Render monitor.snapshot to show the counts and chats.
monitor.open(row.id)
// Codex's read update clears a finished chat.
```

## Files

- `CodexMonitor.swift` reads the catalog, manages the socket connection, and converts updates into `SourceEvent` values. `PulseMonitor` applies those events, publishes snapshots, and saves tracking metadata.
- `PulseState.swift` decides which chats to track and calculates the counts. It also groups chats by status, nests side chats, and splits lists into pages.
- `MenuBarController.swift` manages the menu bar item and panel. It handles positioning, toggle clicks, outside clicks, and dismissal.
- `Presentation.swift` renders the panel and its controls. It asks the monitor to open chats and leaves unread state to Codex.
- `Main.swift` launches the app or runs the short metadata diagnostic.

## Local connection

The adapter uses Codex's private protocol. A Codex update may require an adapter update.

1. Read `~/.codex/state_5.sqlite` every two seconds. Select nonarchived rows with originator `Codex Desktop` or `codex_work_desktop` and source `vscode`, `cli`, or `appServer`. Validate each chat ID as a UUID. Project membership and chat age do not affect discovery. The Work originator fixes the missing Recents chats.
2. Connect to `~/.codex/ipc/ipc.sock`. Each frame has a UInt32 little-endian length and UTF-8 JSON. Reject frames larger than 64 MiB.
3. Initialize as `little-brain` and follow each local chat with `thread-stream-following-changed` version 1.
4. Read `thread-stream-state-changed` version 11 snapshots and patches. Keep the title, runtime status, unread state, turn generation, and parent references. Discard chat bodies.
5. Accept patches only from the snapshot's sender and at the expected base revision. History patches advance the revision even when the adapter discards their content. A revision gap marks the status stale and requests a snapshot.
6. Request a snapshot after a read-state broadcast. Only a snapshot or patch from the established sender changes unread state.
7. Refresh subscriptions every 15 seconds. Disconnects, missing replies, and incompatible data mark the status unavailable.

Codex also announces IDs that other local clients follow. If an ID is absent from SQLite, littlebrain requests its snapshot. It adds the chat only if the snapshot confirms `sideConversation: true`, `ephemeral: true`, and `threadSource: user`. This excludes background subagents. Snapshot creation timestamps use milliseconds.

Each temporary chat keeps a set of clients that follow it. The chat remains while at least one client follows it. When the last client leaves, littlebrain removes the temporary chat and its subscription. Codex replays these announcements after reconnecting.

A successful catalog read removes saved chats that were archived or deleted. A failed read retains the previous catalog. Tracking metadata lives in `~/Library/Application Support/little-brain/tracking.json`. Restored chats stay stale until Codex confirms their status.

## Counter rules

Active chats and chats waiting for input join the tracked list. A tracked chat that finishes with an unread reply goes into Ready for review. Opening it removes it after Codex confirms the read update. Opening a running chat keeps it tracked. A new turn updates the existing row.

The header shows finished unread chats divided by all tracked chats. Waiting and error states go into Ready for review without increasing the header's finished count. Stale chats keep their last group and show an unavailable symbol. `notLoaded` does not mean finished.

On first observation, littlebrain excludes saved unread chats created before monitoring began. New activity, a new turn, or a read-to-unread transition can add them. Saved tracking preserves the monitoring start and previous observations across restarts. Temporary unread side chats can join on their first observation.

Opening a row sends `codex://threads/<UUID>`. The counter waits for Codex's read update.

## Side chats and pages

A side chat's immediate parent comes from `forkedFromId`. If absent, a validated local `sideConversationParentNavigationPath` supplies the parent. Ordinary forks remain separate chats.

Each status section includes its tracked chats and the parents needed to identify them. A running parent can also appear as a label above its finished side chat in Ready for review. Parent labels do not increase the counts. Closed or idle parents remain labels while their descendants are tracked. Side chats use the label Side chat at every level. Cycle detection prevents repeated rows. Visible indentation stops after six levels, while accessibility retains the full depth.

The panel grows to fit its rows up to the screen height. It never scrolls. Previous and next buttons handle longer lists and repeat parent labels when needed. Section counters show totals across all pages.

## Panel behavior

The status button toggles the panel on mouse-down. Outside-click handling uses the full status-item window, including its top edge. The button's smaller bounds only position the panel. Clicking outside the status item and panel dismisses it. Selecting a chat or pressing Escape also dismisses it. Opening the app shows the panel if it is closed. Status updates resize a visible panel without opening it.

The panel uses native glass, the blue logo, and the wordmark. Reduced motion disables spinner and scale animations. Reduced transparency uses a solid system background. Each chat row is one accessibility button. Launch at login and Quit sit in the footer.

## Limits

The app supports local desktop chats and their open temporary side chats. Remote hosts and ChatGPT cloud conversations need separate status sources. The app does not infer activity or read state from rollout files because a crash or delayed write can leave those files out of date.
