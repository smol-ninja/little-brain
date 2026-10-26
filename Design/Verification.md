# Verification — 2026-10-26

## Behavioral contracts

Seven focused XCTest cases cover distinct failure risks:

- Five running chats progress from 0/5 to 1/5 to 5/5; reading one yields 4/4; duplicate read updates are idempotent.
- Viewing while running retains the chat; rerunning a ready chat replaces its state without duplicating it.
- Historical unread backlog is excluded; new-generation and newly created fast completions are admitted.
- Serialized tracking restores stale, preserves unread completion, and clears only after fresh read evidence.
- Disconnect/notLoaded never invent completion; fresh snapshots restore authority; archive removal clears membership.
- Approval/input and system errors do not inflate the ready count.
- A real Unix-socket fixture exercises fragmented framing, ignored history patches with revision advancement, atomic completion/read batches, revision-gap invalidation and resnapshot, cross-client read invalidation, and disconnect.

The domain tests own counter semantics. The socket fixture covers a distinct transport boundary that those tests cannot reach. No test-only production exports or flags were added.

## Installed-app checks

- The native binary's diagnostic connected to the running Codex socket and identified this chat as active, plus existing idle/read and idle/unread chats.
- Initial app tracking excluded the historical unread backlog and showed 0/1.
- Another top-level chat became active during validation and was automatically adopted, producing 0/2.
- Temporarily marked an already-read completed chat unread using Codex's normal app tool: the popover showed 1/3.
- Clicked its actual popover row: Codex opened the correct chat, reported isUnread=false, and Pulse removed the ready row, producing 0/2. The chat's original read state was restored. Running chats remained tracked.
- Returned Codex to the original chat after this check.
- Native popover inspected through its accessibility tree and screenshot. The app uses actual NSGlassEffectView, not a rendered mockup.

Five simultaneous real model jobs were not launched solely to test the counter; the 5-chat sequence is covered at the reducer boundary. Remote and ChatGPT cloud chats are outside the verified scope.

## Final review correction

The reviewer found that the first catalog read after restart did not retire saved chats archived while Pulse was closed. The socket regression was extended with a restored, absent chat and failed on the old implementation (remaining count 1 instead of 0). The source now publishes each successful complete catalog membership set, and the reducer reconciles saved rows against it. Failed catalog reads still preserve tracking. The same regression passes after repair.

During the live check, another real chat transitioned from Working to Ready and changed the popover from 0/2 to 1/2 automatically. Its new unread state was left intact.
