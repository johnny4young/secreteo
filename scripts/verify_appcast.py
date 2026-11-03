#!/usr/bin/env python3
"""Refuses a feed that would offer the wrong update, or one a Mac cannot open or trust.

Usage: verify_appcast.py <feed.xml> <version> <download-url-prefix> <dmg>
"""
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from verify_release import mounted_app

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def feed_problems(feed_xml: str, version: str, prefix: str, dmg_name: str, dmg_size: int) -> list[str]:
    items = list(ET.fromstring(feed_xml).iter("item"))
    matching = [item for item in items if item.findtext(f"{SPARKLE}shortVersionString") == version]
    if len(matching) != 1:
        return [f"expected one item for {version}, found {len(matching)}"]
    item = matching[0]
    problems = []

    versions = [other.findtext(f"{SPARKLE}shortVersionString") or "0" for other in items]
    newest = max(versions, key=lambda value: tuple(int(part) for part in value.split(".")))
    if newest != version:
        problems.append(f"the feed already holds {newest}, newer than {version}")

    if item.findtext(f"{SPARKLE}version") != version:
        problems.append(f"sparkle:version is {item.findtext(f'{SPARKLE}version')!r}, expected {version!r}")
    minimum = item.findtext(f"{SPARKLE}minimumSystemVersion") or ""
    if not minimum.startswith("26"):
        problems.append(f"minimumSystemVersion is {minimum!r}, expected 26.x")
    hardware = (item.findtext(f"{SPARKLE}hardwareRequirements") or "").strip()
    if hardware != "arm64":
        problems.append(f"hardwareRequirements is {hardware!r}, expected arm64")
    if not (item.findtext("description") or "").strip():
        problems.append("release notes are not embedded")

    enclosure = item.find("enclosure")
    if enclosure is None:
        return problems + ["the item has no enclosure"]
    if enclosure.get("url") != f"{prefix}{dmg_name}":
        problems.append(f"enclosure is {enclosure.get('url')}, expected {prefix}{dmg_name}")
    if enclosure.get("length") != str(dmg_size):
        problems.append(f"enclosure length is {enclosure.get('length')}, the DMG has {dmg_size} bytes")
    if not enclosure.get(f"{SPARKLE}edSignature"):
        problems.append("the enclosure has no EdDSA signature")
    return problems


def signature_for(feed_xml: str, version: str) -> str:
    for item in ET.fromstring(feed_xml).iter("item"):
        if item.findtext(f"{SPARKLE}shortVersionString") == version:
            return item.find("enclosure").get(f"{SPARKLE}edSignature")
    raise ValueError(f"no item for {version}")


def main() -> None:
    feed, version, prefix, dmg = Path(sys.argv[1]), sys.argv[2], sys.argv[3], Path(sys.argv[4])
    feed_xml = feed.read_text()
    problems = feed_problems(feed_xml, version, prefix, dmg.name, dmg.stat().st_size)
    if not problems:
        # The key the installed copies will hold is the one in the shipped bundle.
        with mounted_app(dmg) as app:
            public_key = plistlib.loads((app / "Contents/Info.plist").read_bytes())["SUPublicEDKey"]
        checked = subprocess.run(["swift", str(ROOT / "scripts/verify-ed-signature.swift"), public_key,
                                  signature_for(feed_xml, version), str(dmg)], check=False)
        if checked.returncode != 0:
            problems.append("the EdDSA signature does not verify against the DMG and its public key")
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        sys.exit(1)
    print(f"Verified the appcast item for {version}")


if __name__ == "__main__":
    main()
