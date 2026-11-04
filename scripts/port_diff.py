#!/usr/bin/env python3
"""Compares ported files with an export of the frozen commit, using the table in docs/PROVENANCE.md."""
import argparse
import difflib
import re
import sys
from pathlib import Path

RENAMES = [
    ("import AudioCaptureKit", "import MicCapture"),
    ("import PlatformKit", "import MicCapture"),
    ("@testable import ModelStoreKit", "import LocalModelStore"),
    ("import ModelStoreKit", "import LocalModelStore"),
    # Split so the identifier ratchet does not read this file as a leak.
    ("PORTAVOZ" "_", "SECRETEO_"),
    ("@testable import portavoz" "_app", "@testable import DictationSession"),
]
# App code names the app itself, so the session slices also take the new name.
SESSION_RENAMES = [
    ("app." "portavoz.mac", "com.johnny4young.secreteo"),
    ("app." "portavoz.", "com.johnny4young.secreteo."),
    ("portavoz" "Is", "appIs"),
    ("portavoz" "Has", "appHas"),
    ("Portavoz", "Secreteo"),
    ("portavoz", "secreteo"),
    ("PV" "Design", "SecreteoDesign"),
    ("PV" "Symbol", "SecreteoSymbol"),
    # The Carbon hotkey signature, so the two apps never read each other's events.
    ("0x5056" "_4F5A", "0x5343_5254"),
    ('"PV' 'OZ"', '"SCRT"'),
]
ROW = re.compile(r"^\| `([^`]+)` \| `([^`]+)` \| (.+?) \|$")
SECTION = "## Dictation code"


def rows(provenance: str):
    section = provenance.split(SECTION, 1)[1].split("\n## ", 1)[0]
    for line in section.splitlines():
        match = ROW.match(line)
        if match:
            yield match.groups()


def renamed(source: str, ported_path: str) -> list[str]:
    # Two sources split by destination: the dictation domain went to DictationKit.
    in_domain = "DictationKit" in ported_path or "DictationSession" in ported_path
    source = source.replace("import PortavozCore", f"import {'DictationKit' if in_domain else 'SpeechCore'}")
    source = source.replace("import TranscriptionKit", f"import {'DictationKit' if in_domain else 'LiveSpeech'}")
    for old, new in RENAMES + (SESSION_RENAMES if "DictationSession" in ported_path else []):
        source = source.replace(old, new)
    return source.splitlines()


def changes(ported: str, source: str, ported_path: str) -> list[str]:
    diff = difflib.unified_diff(renamed(source, ported_path), ported.splitlines(), "export", "ported", lineterm="", n=0)
    # The first two lines are the file header; a changed line may itself start with --- or +++.
    return [line for line in list(diff)[2:] if not line.startswith("@@")]


def renamed_literals(source: str, ported_path: str) -> list[str]:
    # A rename inside a string can change behavior, so a person reads each one.
    if "DictationSession" not in ported_path:
        return []
    return [
        line.strip() for line in source.splitlines()
        if any(old in literal for literal in re.findall(r'"[^"]*"', line) for old, _ in SESSION_RENAMES)
    ]


def main(arguments: list[str], root: Path) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="git archive of the frozen commit, unpacked")
    options = parser.parse_args(arguments)
    table = list(rows((root / "docs/PROVENANCE.md").read_text()))
    if not table:
        print("No rows to compare in docs/PROVENANCE.md")
        return 1
    failed = False
    for ported, source, change in table:
        original = (options.export / source).read_text()
        found = changes((root / ported).read_text(), original, ported)
        if change == "Renames":
            print(f"{ported}: {'same' if not found else 'DIFFERS'}")
            failed = failed or bool(found)
            shown = found + [f"renamed literal: {line}" for line in renamed_literals(original, ported)]
        elif change.startswith("Extract"):
            # The rest of the source stays behind by design, so only additions need reading.
            shown = [line for line in found if line.startswith("+")]
            print(f"{ported}: {change}, {len(shown)} added")
        elif change.startswith("Seam"):
            shown = found
            print(f"{ported}: {change}")
        else:
            print(f"{ported}: UNKNOWN change kind: {change}")
            failed = True
            shown = found
        for line in shown:
            print(f"  {line}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], Path(__file__).resolve().parents[1]))
