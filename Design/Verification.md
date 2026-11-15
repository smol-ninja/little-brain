# Testing

Run the automated checks:

```sh
swift test
./build.sh
codesign --verify --deep --strict ../little-brain.app
```

The tests cover counter updates, read confirmation, restarts, stale status, side chat nesting, pagination, and saved-chat discovery across Recents and projects. The status-item test checks the measured button and window bounds, including the top edge and adjacent items. Socket tests use a temporary SQLite database and Unix socket. They check fragmented frames, revision gaps, snapshot refreshes, and exclusion of archived chats, subagents, and unrelated app origins.

After installing a build, check the following in Codex:

- Start several local chats, then launch littlebrain while they are running. Confirm that it lists them under Running and the counter stays connected.
- Let a chat finish. Confirm that it moves to Ready for review and increases the finished count.
- Open the finished chat. Confirm that Codex's read update removes it. Opening a running chat should keep it listed.
- Create a side chat. Confirm that it appears beneath its parent and uses the label Side chat.
- Open and close the panel from the center and top edge of the menu bar icon. Repeat several times. Each click should toggle once.
- Dismiss the panel with Escape, an outside click, and a chat selection.
- Check that ten tracked chats fit on one page, including side chats and any parent labels. Add an eleventh chat and use the page buttons to reach it without scrolling.
- Restart littlebrain. Confirm that tracked chats recover after fresh status arrives. Quit Codex and confirm that littlebrain shows unavailable status instead of completion.

Test the top-edge click by hand if your UI automation tool cannot reach the menu bar.
