#!/usr/bin/env python3
"""Compares ported files with an export of the frozen commit, using the table in docs/PROVENANCE.md."""
import argparse
import difflib
import re
import sys
from pathlib import Path

RENAMES = [
    ("import TranscriptionKit", "import DictationKit"),
    ("import AudioCaptureKit", "import MicCapture"),
    ("import PlatformKit", "import MicCapture"),
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
    # Core split in two: the dictation domain went to DictationKit and the rest to SpeechCore.
    core = "DictationKit" if "DictationKit" in ported_path else "SpeechCore"
    source = source.replace("import PortavozCore", f"import {core}")
    for old, new in RENAMES:
        source = source.replace(old, new)
    return source.splitlines()


def changes(ported: str, source: str, ported_path: str) -> list[str]:
    diff = difflib.unified_diff(renamed(source, ported_path), ported.splitlines(), "export", "ported", lineterm="", n=0)
    return [line for line in diff if not line.startswith(("---", "+++", "@@"))]


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
        found = changes((root / ported).read_text(), (options.export / source).read_text(), ported)
        if change == "Renames":
            print(f"{ported}: {'same' if not found else 'DIFFERS'}")
            failed = failed or bool(found)
            shown = found
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
