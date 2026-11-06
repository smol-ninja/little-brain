# Testing

Run the automated checks:

```sh
swift test
./build.sh
codesign --verify --deep --strict ../little-brain.app
```

The tests cover counter updates, read confirmation, restarts, stale status, side chat nesting, pagination, and saved-chat discovery across Recents and projects. Socket tests use a temporary SQLite database and Unix socket. They check fragmented frames, revision gaps, snapshot refreshes, and exclusion of archived chats, subagents, and unrelated app origins.

After installing a build, check the following in Codex:

- Start several local chats. Confirm that littlebrain lists them under Running.
- Let a chat finish. Confirm that it moves to Ready for review and increases the finished count.
- Open the finished chat. Confirm that Codex's read update removes it. Opening a running chat should keep it listed.
- Create a side chat. Confirm that it appears beneath its parent and uses the label Side chat.
- Open and close the panel from the center and top edge of the menu bar icon. Repeat several times. Each click should toggle once.
- Dismiss the panel with Escape, an outside click, and a chat selection.
- Check a list longer than the screen. The page buttons should reach every chat without scrolling.
- Restart littlebrain. Confirm that tracked chats recover after fresh status arrives. Quit Codex and confirm that littlebrain shows unavailable status instead of completion.

Some UI automation tools cannot click menu bar items at the screen edge. A successful panel launch or geometry test does not replace the top-edge click check.
