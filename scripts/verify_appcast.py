#!/usr/bin/env python3
"""Refuses a feed that would offer the wrong update, or one a Mac cannot open.

Usage: verify_appcast.py <feed.xml> <version> <download-url-prefix> <dmg>
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def feed_problems(feed_xml: str, version: str, prefix: str, dmg_name: str, dmg_size: int) -> list[str]:
    items = list(ET.fromstring(feed_xml).iter("item"))
    matching = [item for item in items if item.findtext(f"{SPARKLE}shortVersionString") == version]
    if len(matching) != 1:
        return [f"expected one item for {version}, found {len(matching)}"]
    item = matching[0]
    problems = []

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


def main() -> None:
    feed, version, prefix, dmg = Path(sys.argv[1]), sys.argv[2], sys.argv[3], Path(sys.argv[4])
    problems = feed_problems(feed.read_text(), version, prefix, dmg.name, dmg.stat().st_size)
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        sys.exit(1)
    print(f"Verified the appcast item for {version}")


if __name__ == "__main__":
    main()
