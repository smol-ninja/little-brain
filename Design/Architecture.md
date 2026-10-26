# Architecture

little-brain derives its counter from the running Codex desktop app's local status and unread signals. The local SQLite catalog discovers chats; it does not determine whether they are running.

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
- `Presentation.swift` renders the counter, chat titles, and a two-item options menu inside `NSGlassEffectView`. It asks the monitor to navigate and never edits unread state.
- `Main.swift` launches the app or its short metadata-only diagnostic.

## Local integration

The installed protocol was verified on 2026-10-26. It is internal and versioned, so a Codex update may require changes to this adapter.

1. Enumerate all nonarchived top-level Codex Desktop chats from `~/.codex/state_5.sqlite` using read-only SQLite. No recency cutoff excludes older active chats. Repeat discovery every two seconds.
2. Connect to the existing `~/.codex/ipc/ipc.sock`. Frames are UInt32 little-endian lengths followed by UTF-8 JSON. The adapter bounds incoming frames to 64 MiB.
3. Initialize as client type `little-brain`. Follow known IDs with `thread-stream-following-changed` version 1.
4. Read `thread-stream-state-changed` version 11 snapshots and revisioned patches. Retain only title, runtime status, unread state, and generation metadata; discard chat bodies.
5. Accept patch batches only from the established owner at the expected base revision. Unrelated history patches still advance the revision. A gap invalidates freshness and requests another snapshot.
6. Treat read-state broadcasts as refresh requests, not a second writer of unread state. This avoids applying unordered updates from another account or client.
7. Refresh subscriptions every 15 seconds. Disconnects, lost owners, schema changes, and missing refresh replies leave rows visibly stale instead of inventing completion.

A complete successful catalog read publishes its membership set. The reducer reconciles persisted rows against it, including chats archived or deleted while Pulse was closed. A failed read never masquerades as an empty catalog.

## Counter rules

Active chats join the cohort. Active and read chats remain tracked. Idle and unread tracked chats become Ready; idle and read chats leave. A new generation updates the existing row without duplicating it. Initial historical unread chats are excluded, while subsequently observed activity is admitted. Persisted baselines and membership support restart reconciliation.

`notLoaded` is unavailable, not completed. Approval and input flags receive an attention state. A system error does not inflate the ready count. Ready means finished and unread, not necessarily successful.

Opening a row uses `codex://threads/<UUID>`. The counter waits for Codex's confirmed read update rather than decrementing optimistically.

## Design choice

The design compared two sources: a live IPC follower and an observer of rollout files plus persisted unread arrays. The live follower became the starting design because it provides direct activity and read evidence. The app saves tracked chats and marks them stale until it can confirm their status after restart.

File inference was rejected as a fallback: an unmatched task start can survive a crash, and delayed unread persistence cannot reliably distinguish an unseen completion from one already viewed. Silently switching sources would change the meaning of the counter.

Accessibility scraping was also rejected because background and collapsed chats are difficult to observe and it requires extra permission. A separate app-server process does not own the desktop's current sessions.

## Limits

Only top-level local Codex chats are supported. Remote-host and ChatGPT cloud conversations need independently verified sources. Full snapshots arrive transiently over the local socket, although only small metadata projections are retained. The companion has no public stable Codex API to rely on; incompatibility is surfaced visibly.
