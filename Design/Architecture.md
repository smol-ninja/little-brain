# Architecture

little-brain derives its counter from the running Codex desktop app's local status and unread signals. The local SQLite catalog supplies saved chat IDs and titles, and live following announcements discover temporary chats. Neither discovery source determines whether a chat is running.

## Usage

```swift
let monitor = PulseMonitor(configuration: .localDefault)
monitor.start()
// Render monitor.snapshot; both counts derive from its rows.
monitor.open(row.id)
// Opening dispatches a deep link. Only Codex's read signal clears a row.
```

## Ownership

- `PulseState.swift` owns cohort membership, baseline observations, and the counter rules as value types. It restores saved rows as stale and reconciles them with fresh source evidence.
- `CodexMonitor.swift` owns the source adapter and `PulseMonitor`. A serial socket worker handles POSIX I/O outside the UI and cooperative executor. The adapter projects wire state into domain events. `PulseMonitor` alone applies those events, publishes snapshots, and persists companion metadata.
- `MenuBarController.swift` owns the status item, glass panel, positioning, and dismissal lifecycle.
- `Presentation.swift` renders the logo, counter, chat titles, and inline login and quit controls. It asks the monitor to navigate and never edits unread state.
- `Main.swift` launches the app or its short metadata-only diagnostic.

## Panel interaction

The status button and panel form one interaction surface. `MenuBarController` owns both; the app delegate only connects it to the chat monitor.

- A left mouse-down on the status button toggles the panel. Mouse-up has no action.
- Outside-click observers ignore the screen bounds of both the button and the panel. macOS can deliver a status-item press through the global observer, so window identity alone is insufficient.
- Observers exist only while the panel is visible. Every dismissal removes them and clears the status button highlight.
- Escape uses the panel's native `cancelOperation`, leaving native menus in charge of their own keyboard handling.
- Opening the app calls an idempotent `show`; it cannot close an already open panel. Selecting a chat dismisses through the same controller.
- Snapshot updates change the counter and resize a visible panel. They never open it.

This replaces the separate mouse-down dismissal and mouse-up toggle that could close and reopen the panel during a single click. The glass panel hosts the presentation without owning chat or login state.

## Appearance

The blue glass logo appears in the panel header and beside the menu-bar counter. The header pairs the name with a large unread count and a smaller total. The inset list has two sections, Ready for review and Running, with status symbols and hover feedback. Finished unread chats and chats needing input or error review go in the first section. Active chats go in Running. Stale rows keep their last group and show an unavailable symbol. Section counts include tracked chats in that group; the header numerator still counts only finished unread chats. Parent labels added for context do not affect either counter. Launch at login and Quit sit directly in the footer; there is no options menu.

`PanelMetrics` defines the width, corner radius, and section heights used by both SwiftUI and the window controller. The panel grows with its displayed rows, including parent labels, up to the available screen height. It has no scroll container. If the rows exceed that height, previous/next buttons in the footer page through them. Continued side chats repeat their parent labels, and section counters still show the full tracked totals. Native glass supplies the background; a faint blue reflection and edge highlight echo the logo. Reduced motion disables the spinner and scale animations, and reduced transparency uses a solid system background. Status symbols are hidden from accessibility so each row remains one named button.

## Local integration

The installed protocol was verified on 2026-10-26. It is internal and versioned, so a Codex update may require changes to this adapter.

1. Enumerate all nonarchived top-level Codex Desktop chats from `~/.codex/state_5.sqlite` using read-only SQLite. No recency cutoff excludes older active chats. Repeat discovery every two seconds.
2. Connect to the existing `~/.codex/ipc/ipc.sock`. Frames are UInt32 little-endian lengths followed by UTF-8 JSON. The adapter bounds incoming frames to 64 MiB.
3. Initialize as client type `little-brain`. Follow known IDs with `thread-stream-following-changed` version 1.
4. Read `thread-stream-state-changed` version 11 snapshots and revisioned patches. Retain title, runtime status, unread state, generation metadata, and parent references; discard chat bodies.
5. Accept patch batches only from the established owner at the expected base revision. Unrelated history patches still advance the revision. A gap invalidates freshness and requests another snapshot.
6. Treat read-state broadcasts as refresh requests, not a second writer of unread state. This avoids applying unordered updates from another account or client.
7. Refresh subscriptions every 15 seconds. Disconnects, lost owners, schema changes, and missing refresh replies leave rows visibly stale instead of inventing completion.

Codex replays its live following announcements to newly connected clients. For an announced local ID absent from SQLite, the adapter follows the ID and admits it only after a snapshot confirms `sideConversation: true`, `ephemeral: true`, and `threadSource: user`. This excludes background subagents. Creation timestamps in these snapshots are milliseconds. A confirmed temporary chat uses the same counter rules and navigation as other chats. Its row is labeled Side chat and nested under its parent.

The adapter tracks the announcing clients for each temporary chat. Closing one view keeps the chat if another remains. When the last viewer stops following or disconnects, the adapter removes that temporary chat and its subscription. On reconnect, Codex's announcements rebuild this catalog. An initially unread temporary chat is admitted even if it predates littlebrain, so restarting the companion does not lose its unread reply.

A complete successful catalog read publishes the union of saved and confirmed temporary IDs. The reducer reconciles persisted rows against it, including chats archived or deleted while Pulse was closed. A failed read never masquerades as an empty catalog.

## Chat hierarchy

Side chats take their immediate parent from `forkedFromId`. If that ID is absent, a validated local `sideConversationParentNavigationPath` supplies the parent. These references apply only when Codex marks the conversation as a side chat; ordinary forks stay independent.

Each section builds an outline from its tracked members and their ancestors. A running main chat with a finished side chat appears as a context label under Ready for review and as a tracked row under Running. Idle or closed ancestors remain context labels while descendants are tracked. Every side-chat level uses the label Side chat, with indented cards and connecting lines. Nesting is derived recursively, with cycle protection. Visual indentation stops increasing after six levels to preserve room for labels, while accessibility retains the actual level.

Catalog titles name parents whose runtime snapshot has not loaded. Saved observations preserve ancestry across restart. Context rows never count as extra chats, and window height uses the displayed outline length rather than the counter total.

## Counter rules

Active chats join the cohort. Active and read chats remain tracked. Idle and unread tracked chats become Ready; idle and read chats leave. A new generation updates the existing row without duplicating it. Initial historical unread saved chats are excluded, while subsequently observed activity is admitted. Persisted baselines and membership support restart reconciliation.

`notLoaded` is unavailable, not completed. Approval and input flags receive an attention state. A system error does not inflate the ready count. Ready means finished and unread, not necessarily successful.

Opening a row uses `codex://threads/<UUID>`. The counter waits for Codex's confirmed read update rather than decrementing optimistically.

## Design choice

The design compared two sources: a live IPC follower and an observer of rollout files plus persisted unread arrays. The live follower became the starting design because it provides direct activity and read evidence. The app saves tracked chats and marks them stale until it can confirm their status after restart.

File inference was rejected as a fallback: an unmatched task start can survive a crash, and delayed unread persistence cannot reliably distinguish an unseen completion from one already viewed. Silently switching sources would change the meaning of the counter.

Accessibility scraping was also rejected because background and collapsed chats are difficult to observe and it requires extra permission. A separate app-server process does not own the desktop's current sessions.

## Limits

Local Codex chats and their open temporary conversations are supported. Background subagents are excluded. Remote-host and ChatGPT cloud conversations need independently verified sources. Full snapshots arrive transiently over the local socket, although only small metadata projections are retained. The companion has no public stable Codex API to rely on; incompatibility is surfaced visibly.
