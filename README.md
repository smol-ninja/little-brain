# Codex Pulse

A native macOS menu bar companion for local Codex chats. Built for macOS 26 or later; this build targets Apple Silicon.

## Use

Build the app using the instructions below, then move `Codex Pulse.app` into `/Applications`. Open it and look for the small ring and `x/y` counter in your menu bar. Click the counter to open the glass panel. Opening the app again from Finder also opens the panel.

- `0/5`: five chats are working.
- `3/5`: three have finished and are unread; two are still working.
- `5/5 → 4/4`: opening one finished chat removes it after Codex confirms it was viewed.
- Opening a running chat keeps it tracked.
- A new turn in a tracked chat returns that same row to Working.
- Approval and input requests appear in amber.
- `—/N` means status is unavailable; previous tracking is retained until it can be confirmed.

Click any row to open the corresponding chat in Codex. Viewing it directly in Codex has the same effect. “Ready” means finished and unread, not a guarantee that the task succeeded.

The first launch adopts running chats and follows new activity. It does not import your old unread backlog. Tracking survives restarts. Archived/deleted chats leave the counter when the local catalog confirms removal.

The **⋯** menu offers **Launch at login** and **Quit Codex Pulse**. Launch at login is off initially. Escape or clicking outside closes the panel. Keyboard Tab/Return can select and open a chat. The interface follows macOS appearance and Reduce Motion.

## Scope and privacy

This version covers top-level **local Codex chats on this Mac**. It excludes subagents, remote hosts, and ChatGPT cloud conversations.

It joins Codex's existing local coordination socket as a passive follower and reads the thread catalog in read-only mode. It does not edit Codex files, submit prompts, approve requests, or need Accessibility or Screen Recording permission. No network service or API key is used.

The internal Codex protocol is versioned but not a public stable API. If a future update changes it, Pulse shows an unavailable/update-needed state. It does not guess success from old session logs. Full chat state can arrive transiently over the local socket; Pulse discards conversation bodies and retains only title/status/unread/generation metadata. Its own tracking file is `~/Library/Application Support/Codex Pulse/tracking.json`.

## Build and check

Requires Xcode/Swift with the macOS 26+ SDK. No third-party packages.

```sh
./build.sh
swift test
```

The build script creates `Codex Pulse.app` beside this source folder and signs it locally with an ad-hoc signature. It is a local build, not an Apple-notarized distribution. `PULSE_BUILD_DIR` can point to a persistent scratch directory, and `PULSE_APP_PATH` can choose the output app location.

For a metadata-only live connection diagnostic:

```sh
"../Codex Pulse.app/Contents/MacOS/CodexPulse" --diagnose
```

The diagnostic runs for eight seconds and prints IDs, runtime state, and unread flags; it does not print message bodies.

## Architecture and verification

[Architecture](Design/Architecture.md) describes the implementation and the alternatives considered. [Verification](Design/Verification.md) records the behavioral and live UI checks.

The app uses Apple's native [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview), including interactive glass on macOS 27, with SwiftUI content and animated count transitions.

## Remove

Quit from the **⋯** menu, disable Launch at login if enabled, then move `Codex Pulse.app` to Trash. Removing `~/Library/Application Support/Codex Pulse` clears only this companion's saved tracking.
