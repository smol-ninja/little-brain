# Architecture

littlebrain reads chat IDs and titles from Codex's local SQLite database. It subscribes to runtime and unread updates for those IDs through Codex's local socket.

## Files

- `CodexMonitor.swift` reads the catalog, manages the socket connection, and converts updates into `SourceEvent` values. `PulseMonitor` applies those events, publishes snapshots, and saves tracking metadata.
- `PulseState.swift` decides which chats to track and calculates the counts. It also groups chats by status, nests side chats, and splits lists into pages.
- `MenuBarController.swift` manages the menu bar item and panel. It handles positioning, toggle clicks, outside clicks, and dismissal.
- `Presentation.swift` renders the monitor's snapshot. It calls `open(_:)` when someone selects a chat.
- `Main.swift` launches the app or runs the short metadata diagnostic.

## Local connection

The adapter uses Codex's private protocol. A Codex update may require an adapter update.

1. Read `~/.codex/state_5.sqlite` every two seconds. Select nonarchived rows with originator `Codex Desktop` or `codex_work_desktop` and source `vscode`, `cli`, or `appServer`. Accept valid UUIDs for chats of any age, with or without a project.
2. Connect to `~/.codex/ipc/ipc.sock`. Each frame has a 32-bit unsigned little-endian length followed by UTF-8 JSON. Reject frames larger than 64 MiB.
3. Initialize as `little-brain` and follow each local chat with `thread-stream-following-changed` version 1.
4. Read `thread-stream-state-changed` snapshots and patches for versions 11 and 13. Keep the title, runtime status, unread state, turn generation, and parent references. Discard chat bodies.
5. Accept patches only from the snapshot's sender and at the expected base revision. History patches advance the revision even when the adapter discards their content. A revision gap marks the status stale and requests a snapshot.
6. Request a snapshot after a read-state broadcast. Update unread state from snapshots and accepted patches.
7. Refresh subscriptions every 15 seconds. If a refresh request goes unanswered for five seconds, mark the chat's last known status stale. Retry the connection after a disconnect or an unsupported protocol version.

Codex also announces IDs that other local clients follow. If an ID is absent from SQLite, littlebrain requests its snapshot. It adds the chat only if the snapshot confirms `sideConversation: true`, `ephemeral: true`, and `threadSource: user`. This excludes background subagents. Snapshot creation timestamps use milliseconds.

littlebrain keeps a temporary chat while another client follows it. When the last client stops following or disconnects, littlebrain removes the chat and its subscription. Codex replays these announcements after reconnecting.

A successful catalog read removes saved chats that were archived or deleted. A failed read retains the previous catalog. Tracking metadata lives in `~/Library/Application Support/little-brain/tracking.json`. Restored chats stay stale until Codex confirms their status.

## Counter rules

Active chats and chats waiting for input join the tracked list. A tracked chat that finishes with an unread reply moves to Ready for review. A new turn updates its existing row.

The header shows finished unread chats divided by all tracked chats. Waiting and error states go into Ready for review without increasing the header's finished count. Stale chats keep their last group and show an unavailable symbol. `notLoaded` does not mean finished.

If littlebrain first sees an idle, unread saved chat created before monitoring began, it leaves it out of the count. Activity, a new turn, or a change from read to unread can add it later. littlebrain saves the monitoring start time and previous observations across restarts. Temporary unread side chats can join on the first update.

Selecting a row opens `codex://threads/<UUID>`. A finished chat leaves the count after Codex reports it as read. A running chat stays in the list.

## Side chats and pages

A side chat's immediate parent comes from `forkedFromId`. If absent, a validated local `sideConversationParentNavigationPath` supplies the parent. Ordinary forks remain separate chats.

Each section lists its tracked chats and adds parent labels where needed. For example, a running parent can appear as a label above a finished side chat in Ready for review. Closed or idle parents remain as labels while littlebrain tracks their descendants. The tally excludes these extra labels. The panel labels each side chat Side chat. The outline shows each chat once per section, even if parent links form a cycle. Indentation stops after six levels. VoiceOver announces the full depth.

The panel grows to fit its rows up to the screen height. Use the Previous and Next buttons to page through longer lists without scrolling. A new page can repeat parent labels above a side chat. Section counters show totals across all pages.

## Panel behavior

The status button toggles the panel on left mouse-down. The outside-click handler treats the full status-item window, including its top edge, as part of the button. The button's smaller bounds position the panel. Clicking outside both windows, selecting a chat, or pressing Escape dismisses the panel. Opening the app shows the panel. Status updates resize it while it is open.

The panel uses native glass, the blue logo, and the wordmark. Reduced motion disables spinner and scale animations. Reduced transparency uses a solid system background. Each chat row is one accessibility button. Launch at login and Quit sit in the footer.

## Limits

The app tracks local desktop chats and their open temporary side chats. For activity and read state, it uses the socket because a crash or delayed write can leave rollout files out of date.
