#!/usr/bin/env python3
"""Verify a release's signed feed and DMG, including rejection of modified copies."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("release_directory", type=Path)
parser.add_argument("--sparkle-account", default="littlebrain")
args = parser.parse_args()
release = args.release_directory.resolve()
tools = release / "build/artifacts/sparkle/Sparkle/bin"
feed = release / "appcast.xml"
image = release / "littlebrain.dmg"
signature = ET.parse(feed).find("channel/item/enclosure").attrib[
    "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"]
command = [str(tools / "sign_update"), "--account", args.sparkle_account, "--verify"]
subprocess.run(command + [str(feed)], check=True)
subprocess.run(command + [str(image), signature], check=True)
with tempfile.TemporaryDirectory(prefix="littlebrain-tamper-") as directory:
    for original, suffix in [(feed, []), (image, [signature])]:
        modified = Path(directory) / original.name
        shutil.copy2(original, modified)
        if original == feed:
            modified.write_bytes(modified.read_bytes().replace(b"<title>", b"<title>Modified ", 1))
        else:
            with modified.open("r+b") as target:
                target.seek(100)
                byte = target.read(1)
                target.seek(100)
                target.write(bytes([byte[0] ^ 1]))
        result = subprocess.run(command + [str(modified)] + suffix, capture_output=True, text=True)
        if result.returncode == 0:
            raise SystemExit(f"ERROR: altered {original.name} was accepted")
        print(f"Altered {original.name} rejected.")
print("Original feed and installer accepted. Both modified copies rejected.")
