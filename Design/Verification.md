# Verification

Run `swift test` to check the counter and local socket connection.

The tests cover five running chats, completion, viewing a finished chat, rerunning a chat, restart recovery, archive removal, approval requests, and disconnects. The socket test checks fragmented frames, revision gaps, and read-state refreshes.

The installed app was checked against Codex on 2026-10-26. Opening a finished chat changed the counter from 1/3 to 0/2. Running chats stayed tracked. A real chat completion also changed the counter from 0/2 to 1/2.

The little-brain update keeps these counting rules and reduces the panel to its name, counter, and chat titles. Its options menu contains Launch at login and Quit.

Version 1.1.1 moves panel interactions into `MenuBarController`. The release build and all seven tests pass. In the installed app, the options menu exposes its two commands, and Escape and selecting a chat dismiss the panel. Window-server inspection confirmed zero visible little-brain windows after each dismissal, without reopening the app to inspect it.

The menu-bar toggle still needs a physical click check: open it, click the same button to close it, then repeat. The automation tool reports `windowNotFoundAtPosition` for the status button, so the exact reported gesture was not reproduced before or after the change. Also check outside clicks and the options menu on the target macOS version.

Version 1.2.0 adds the supplied blue logo, inset chat rows, and inline controls. The installed panel was inspected at 360 points wide with two live chats, including a finished unread state. Accessibility exposes each chat as one button and exposes the login switch and Quit button without a menu. Clicking the power control terminated the process, then the app was relaunched. The login setting was left unchanged. The release build, signature verification, and all seven existing tests pass. `docs/screenshot.png` is a capture of the installed app.

Version 1.3.0 adds Ready for review and Running. The new socket regression failed before the change because the source never subscribed to an announced temporary chat. It now covers unread admission without a SQLite row, multiple viewers, catalog refresh, transitions between running and unread, last-viewer removal, and exclusion of remote chats and subagents. The counter tests also check section placement for completion, input requests, and errors. All eight tests pass.

Live metadata confirmed two local temporary chats absent from SQLite. The installed panel displayed four running chats, including those two, with ordinary titles and no special label. Announcements also remained available after navigating away from the parent chat. The temporary-chat deep link was dispatched, but Codex's window could not be inspected by the UI automation tool, so its final navigation destination remains unverified.

Version 1.4.0 nests Side chat rows by parent ID. Ten tests pass, including mixed-status parents and descendants, recursive nesting, idle and closed ancestor labels, restart persistence, catalog title fallback, missing parents, and cycles. The socket fixture checks the parent-path fallback and that an immediate fork parent takes precedence. All counters exclude context-only ancestor rows.

The native panel was also rendered with example chats to check recursive indentation and parent labels across sections. The README screenshot uses that example snapshot. The installed live panel was checked separately; it had two running main chats and no active side chats at the time. The release build and code-signature verification passed, and version 1.4.0 was installed locally.

Version 1.4.1 removes scrolling and the eight-row height limit. Eleven tests pass; the new pagination test checks that every tracked chat appears exactly once across pages, pages stay within capacity, repeated parents are context only, and an empty list remains valid. In a native preview with 20 example chats, 11 rows fit on the first page, wheel input left the view unchanged, and the next/previous buttons switched pages with the parent label retained. The release build passed.
