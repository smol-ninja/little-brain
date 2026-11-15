#!/usr/bin/env python3
"""Build, sign, and notarize the DMG for GitHub Releases."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSET_NAME = "littlebrain.dmg"


def run(*arguments, **options):
    return subprocess.run(arguments, check=True, text=True, **options)


def make_disk_image(app: Path, image: Path) -> None:
    staging = image.parent / "disk-image"
    staging.mkdir()
    shutil.copytree(app, staging / app.name, symlinks=True)
    (staging / "Applications").symlink_to("/Applications")
    run("hdiutil", "create", "-volname", "littlebrain", "-srcfolder", staging,
        "-format", "UDZO", "-fs", "HFS+", image)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, help="Developer ID Application signing identity")
    parser.add_argument("--notary-profile", required=True, help="notarytool Keychain profile")
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()

    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture_output=True).stdout
    if not args.identity.startswith("Developer ID Application: ") or f'"{args.identity}"' not in identities:
        parser.error("Install a valid Developer ID Application certificate and its private key in Keychain.")

    output = args.output_directory.resolve() / ASSET_NAME
    if output.exists():
        parser.error(f"The output already exists: {output}")

    with tempfile.TemporaryDirectory(prefix="littlebrain-release-") as scratch:
        directory = Path(scratch)
        app = directory / "little-brain.app"
        image = directory / ASSET_NAME
        environment = dict(os.environ, LITTLE_BRAIN_APP_PATH=str(app))
        run("/bin/bash", ROOT / "build.sh", env=environment)
        run("lipo", "-verify_arch", "arm64", app / "Contents/MacOS/LittleBrain")
        run("codesign", "--force", "--sign", args.identity, "--options", "runtime", "--timestamp", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        make_disk_image(app, image)
        run("codesign", "--sign", args.identity, "--timestamp", image)

        submission = run("xcrun", "notarytool", "submit", image, "--keychain-profile", args.notary_profile,
                         "--wait", "--output-format", "json", stdout=subprocess.PIPE)
        result = json.loads(submission.stdout)
        if result.get("status") != "Accepted":
            raise SystemExit(f"Notarization failed: {result.get('status')} (submission {result.get('id')}).")
        run("xcrun", "stapler", "staple", image)
        run("xcrun", "stapler", "validate", image)
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", image)

        output.parent.mkdir(parents=True, exist_ok=True)
        with image.open("rb") as source, output.open("xb") as destination:
            shutil.copyfileobj(source, destination)
        print(output)


if __name__ == "__main__":
    main()
