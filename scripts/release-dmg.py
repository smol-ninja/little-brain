#!/usr/bin/env python3
"""Build, sign, notarize, and generate a signed Sparkle feed. Rerun to resume."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ASSET_NAME = "littlebrain.dmg"
SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def run(*arguments, **options):
    return subprocess.run(arguments, check=True, text=True, **options)


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def save_state(path, state):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(path)


def make_disk_image(app: Path, image: Path) -> None:
    staging = image.parent / "disk-image"
    staging.mkdir()
    shutil.copytree(app, staging / app.name, symlinks=True)
    (staging / "Applications").symlink_to("/Applications")
    run("hdiutil", "create", "-volname", "littlebrain", "-srcfolder", staging,
        "-format", "UDZO", "-fs", "HFS+", image)


def verify_feed(feed, image, info, archive_url, tools, account):
    item = ET.parse(feed).find("channel/item")
    if item is None:
        raise SystemExit("The generated feed has no update.")
    enclosure = item.find("enclosure")
    expected = {
        "version": info["CFBundleVersion"],
        "shortVersionString": info["CFBundleShortVersionString"],
        "minimumSystemVersion": info["LSMinimumSystemVersion"],
    }
    for name, value in expected.items():
        if item.findtext(SPARKLE_NS + name) != value:
            raise SystemExit(f"Feed {name} does not match the built app.")
    if enclosure is None or enclosure.get("url") != archive_url:
        raise SystemExit("Feed URL does not match the version-specific release URL.")
    if int(enclosure.get("length", "0")) != image.stat().st_size:
        raise SystemExit("Feed archive length does not match the DMG.")
    run(tools / "sign_update", "--account", account, "--verify", feed)
    run(tools / "sign_update", "--account", account, "--verify", image,
        enclosure.attrib[SPARKLE_NS + "edSignature"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, help="Developer ID Application signing identity")
    parser.add_argument("--notary-profile", required=True, help="notarytool Keychain profile")
    parser.add_argument("--sparkle-account", default="littlebrain", help="Sparkle signing key in Keychain")
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    directory = args.output_directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    image = directory / ASSET_NAME
    app = directory / "little-brain.app"
    state_path = directory / "release-state.json"
    build = directory / "build"
    tools = build / "artifacts/sparkle/Sparkle/bin"

    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture_output=True).stdout
    if not args.identity.startswith("Developer ID Application: ") or f'"{args.identity}"' not in identities:
        parser.error("Install a valid Developer ID Application identity in Keychain.")
    if os.environ.get("LITTLE_BRAIN_FIXTURE_BUILD") or os.environ.get("LITTLE_BRAIN_FIXTURE_FEED"):
        parser.error("Fixture overrides cannot be used to create a release.")

    if state_path.exists():
        state = json.loads(state_path.read_text())
        if state["identity"] != args.identity:
            parser.error("Resume with the original signing identity.")
        if digest(directory / state["archive"]) != state["sha256"]:
            parser.error("The saved DMG changed. Preserve it and use a fresh output directory.")
    else:
        if image.exists() or app.exists():
            parser.error("Partial build exists. Preserve it and use a fresh output directory.")
        environment = dict(os.environ, LITTLE_BRAIN_APP_PATH=str(app),
                           LITTLE_BRAIN_BUILD_DIR=str(build), LITTLE_BRAIN_SIGN_IDENTITY=args.identity)
        run("/bin/bash", ROOT / "build.sh", env=environment)
        run("lipo", "-verify_arch", "arm64", app / "Contents/MacOS/LittleBrain")
        submission_dir = directory / "notarization"
        submission_dir.mkdir()
        submitted = submission_dir / f"littlebrain-{uuid.uuid4().hex}.dmg"
        make_disk_image(app, submitted)
        run("codesign", "--sign", args.identity, "--timestamp", submitted)
        state = {"identity": args.identity, "archive": str(submitted.relative_to(directory)),
                 "sha256": digest(submitted)}
        save_state(state_path, state)

    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    public_key = run(tools / "generate_keys", "--account", args.sparkle_account, "-p",
                     capture_output=True).stdout.strip()
    if public_key != info["SUPublicEDKey"]:
        parser.error("The Sparkle Keychain key does not match the app's public key.")

    submitted = directory / state["archive"]
    if "submission" not in state:
        receipt = directory / "notary-submission.json"
        if receipt.exists():
            try:
                state["submission"] = json.loads(receipt.read_text())["id"]
            except (ValueError, KeyError):
                history = json.loads(run("xcrun", "notarytool", "history", "--keychain-profile",
                                         args.notary_profile, "--output-format", "json",
                                         capture_output=True).stdout)
                matches = [entry for entry in history["history"] if entry["name"] == submitted.name]
                if len(matches) != 1:
                    raise SystemExit("Submission receipt is incomplete. Preserve this directory and "
                                     "check notarytool history before retrying. No duplicate was submitted.")
                state["submission"] = matches[0]["id"]
        else:
            with receipt.open("w") as output:
                run("xcrun", "notarytool", "submit", submitted, "--keychain-profile",
                    args.notary_profile, "--output-format", "json", stdout=output)
            state["submission"] = json.loads(receipt.read_text())["id"]
        save_state(state_path, state)

    if not state.get("stapled"):
        run("xcrun", "notarytool", "wait", state["submission"], "--keychain-profile",
            args.notary_profile, "--timeout", "20m")
        result = json.loads(run("xcrun", "notarytool", "info", state["submission"],
                                "--keychain-profile", args.notary_profile,
                                "--output-format", "json", capture_output=True).stdout)
        if result["status"] != "Accepted":
            raise SystemExit(f"Notarization {result['status']}. Submission {state['submission']}.")
        # The submitted archive stays immutable so interrupted stapling can be retried.
        pending = directory / "stapled.dmg"
        shutil.copy2(submitted, pending)
        run("xcrun", "stapler", "staple", pending)
        run("xcrun", "stapler", "validate", pending)
        pending.replace(image)
        state.update(stapled=True, final_sha256=digest(image))
        save_state(state_path, state)
    if digest(image) != state["final_sha256"]:
        parser.error("The final DMG changed after stapling.")
    run("xcrun", "stapler", "validate", image)
    run("codesign", "--verify", "--strict", image)
    run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", image)

    version = info["CFBundleShortVersionString"]
    prefix = f"https://github.com/smol-ninja/little-brain/releases/download/v{version}/"
    feed = directory / "appcast.xml"
    with tempfile.TemporaryDirectory(prefix="littlebrain-appcast-") as scratch:
        archives = Path(scratch)
        shutil.copy2(image, archives / ASSET_NAME)
        previous = ROOT / "docs/appcast.xml"
        if previous.exists():
            run(tools / "sign_update", "--account", args.sparkle_account, "--verify", previous)
            shutil.copy2(previous, archives / "appcast.xml")
        (archives / "littlebrain.html").write_text(
            "<p>Update littlebrain from the version button beside Launch at login.</p>")
        run(tools / "generate_appcast", "--account", args.sparkle_account,
            "--maximum-deltas", "0", "--download-url-prefix", prefix, "--embed-release-notes", archives)
        generated = archives / "appcast.xml"
        verify_feed(generated, image, info, prefix + ASSET_NAME, tools, args.sparkle_account)
        pending_feed = directory / "appcast.pending.xml"
        shutil.copy2(generated, pending_feed)
        pending_feed.replace(feed)
    print(f"Verified {image}\nSigned feed: {feed}\nSHA-256: {digest(image)}")


if __name__ == "__main__":
    main()
