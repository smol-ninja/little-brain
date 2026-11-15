# Distribution

GitHub Pages serves `docs/` from `main` at [smol-ninja.github.io/little-brain](https://smol-ninja.github.io/little-brain/). The page shows the download button when the latest stable GitHub release has an uploaded asset named `littlebrain.dmg`.

## Build the installer

Use an Apple silicon Mac with Xcode, a valid Developer ID Application certificate and private key in Keychain, and a `notarytool` Keychain profile. Follow [Apple's Developer ID guide](https://developer.apple.com/developer-id/) to set up signing and notarization credentials.

```sh
python3 scripts/release-dmg.py \
  --identity 'Developer ID Application: Your Name (TEAMID)' \
  --notary-profile littlebrain \
  /path/to/release-output
```

The script builds the app, enables Hardened Runtime, signs the app and disk image, and waits for notarization. It saves `littlebrain.dmg` after stapling the approval ticket and checking it with Gatekeeper. Before publishing, open the DMG on another compatible Mac and confirm that a copy in Applications connects to Codex.

Create a GitHub release whose tag matches `CFBundleShortVersionString` in `build.sh`, with a `v` prefix. Attach the DMG as `littlebrain.dmg`, then publish the release. Keep the asset name the same across versions so the site can find it.

## Updates

Users can download the latest DMG and replace the app in Applications. An in-app updater would require a new app build. [Sparkle](https://sparkle-project.org/documentation/) can check an appcast on GitHub Pages and verify a signed DMG from a versioned GitHub release URL. Publish the appcast after uploading the signed asset.
