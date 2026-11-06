# Recents discovery

## Problem

The local desktop uses two observed producer names: `Codex Desktop` and `codex_work_desktop`. The saved-chat query accepted only the first. Work chats were therefore absent before the live-status and counter rules could run. The query has no project or recency condition.

## Usage (caller's view)

Existing callers keep the same interfaces:

```swift
// The app consumes eligible identities and authoritative status through one stream.
let source = CodexSource(configuration: .localDefault)
for await event in await source.observations() {
    state.apply(event)
}

// Inside the socket worker, discovery still requests a complete saved catalog.
let next = try readCatalog()
```

## Shape

The sketch retains the existing private boundary; no new type or service is needed:

```swift
private func readCatalog() throws -> [String: CatalogEntry] {
    // Sketch: read-only SQLite; select nonarchived rows whose source is
    // vscode, cli, or appServer and whose originator is exactly
    // Codex Desktop or codex_work_desktop. Validate UUIDs, return identities.
    fatalError("not implemented")
}
```

Implementation replaces the single-origin equality with two-value SQL membership. Archive, source, and producer eligibility remain together in the adapter. UUID decoding also stays there. Project membership, runtime, and unread state are not catalog eligibility fields.

`CodexMonitor.swift` remains the sole adapter owner. Its IPC replica validates the local host, snapshot owner, and revision before projecting an `Observation`. `PulseState.swift` retains membership and historical-backlog policy; the UI renders its snapshot. The stream hides storage and transport behind one existing interface, per boundary-discipline. There is no additional pass-through layer or duplicated production allowlist.

## Synthesis decision

Candidate A, query-owned eligibility, is the base. Candidate B moved row metadata into a private Swift type and used a failable conversion for eligibility. Both preserve the public stream, but B adds decoding and a type while scanning unrelated and archived rows every two seconds. A keeps the full saved eligibility predicate together with less code.

The comparison uses five criteria: verified producer coverage, exclusion boundaries, existing authority/admission ownership, interface depth, and executable proof. A scores 5/5 on each; B scores 5/5 except interface proportionality at 3/5. The independent cross-judge also chose A (25/25 versus 22/25), giving A additional credit for its concrete subscription barrier. Both pass the red-flag screen; B's extra row representation does not earn its size here.

The verification plan takes B's explicit project-independence cases and A's synchronization with the existing post-discovery live event. The regression uses actual SQLite and socket subscriptions, rather than a standalone predicate test. The skill's Claude/Grok defaults were unavailable; available GPT models produced the two designs and a separate cross-judge.

## Tradeoffs accepted

- An exact list of verified producer spellings requires review when Codex adds another producer, in exchange for excluding unverified apps and standalone CLI tasks.
- A real SQLite/socket regression needs a small fixture extension, in exchange for exercising the boundary that failed.

## Alternatives considered

A parsed Swift catalog boundary centralizes validation in a failable conversion but exposes another private storage representation without increasing external interface depth. Removing producer filtering entirely would broaden subscriptions to unverified origins. Project-specific discovery would couple eligibility to a sidebar grouping that does not establish chat origin.

## Open questions and risks

Could a future desktop update change producer names or the private IPC protocol? Extend only after verifying its metadata and status contract.

Could an old first-seen unread chat stay absent after discovery succeeds? Yes: the existing historical-backlog policy still applies. The reported Work chat was created after persisted monitoring began, so the existing policy should admit its unread reply.

## Next implementation step

Demonstrate the adapter regression fails on the single-origin query, broaden the predicate, then run the suite and verify the installed app observes the previously excluded chat.
