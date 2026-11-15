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

## Signed updates

The release machine needs a Developer ID Application identity, the `littlebrain` notarytool profile, and the Sparkle private key under Keychain account `littlebrain`. The public key is in `build.sh`. Keep a recoverable private-key backup outside this repository.

```sh
python3 scripts/release-dmg.py --identity 'Developer ID Application: YOUR IDENTITY' \
  --notary-profile littlebrain ../release.noindex
python3 scripts/verify-update.py ../release.noindex
```

The release command keeps its input DMG and notarization receipt. Rerun with the same directory to resume. It verifies the final stapled DMG before generating the signed appcast. Keep only one release process per output directory.

If submission stops before a complete receipt is saved, the script searches Apple's history for the archive's unique filename. It resumes a unique match and refuses an ambiguous retry. If there is no match, wait and check `xcrun notarytool history --keychain-profile littlebrain` again. Only after confirming that Apple received no submission, move the incomplete `notary-submission.json` aside and rerun. Never remove `release-state.json` or replace the submitted DMG to force a retry. A directory created by an older pipeline may use a different state format; preserve it and use a new directory.

Test a release as a prerelease before promoting it. Use a lower-build fixture with the same bundle identity and a separate HTTPS feed. `LITTLE_BRAIN_FIXTURE_BUILD` and `LITTLE_BRAIN_FIXTURE_FEED` are build-only overrides; the release command rejects them. Preserve the installed app and preferences before replacing a local copy.

Verify installation and relaunch, scheduled reminders, automatic installation on quit, cancellation, no-update results, and recovery after connection or signature failures. Confirm the installed version, single running process, resumed chat tracking, and login setting. `verify-update.py` checks the original feed and archive plus modified copies; it does not replace testing the installed updater.

Publish the exact tested DMG at the version-specific GitHub release URL. Remove temporary test assets, promote the release, then copy its generated `appcast.xml` to `docs/appcast.xml` without editing the signed content. Fetch both public files and verify their signatures, size, and SHA-256 against the tested files. Check the website's download button and the installed app's production update check.

Keep earlier signed feeds and installers. To stop offering a faulty update, publish a newly signed feed that omits it. Fix already-updated installations with a higher build number; do not promise automatic downgrade. Users on 1.4.7 or earlier must replace the app from a DMG once to gain the updater.
