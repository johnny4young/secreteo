#!/usr/bin/env python3
"""Usage: ui_test_shards.py <index> <count>

Prints one shard of the UI test classes, one per line, balanced by test count.
Shards are computed from the sources, so a new test class needs no list."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI_TESTS = ROOT / "Tests/SecreteoUITests"
CLASS = re.compile(r"^(?:final )?class (\w+)\s*:", re.M)
TEST = re.compile(r"^\s*func (test\w*)\(", re.M)


def test_classes(root=UI_TESTS):
    """Maps each class that declares tests to its test count."""
    found = {}
    for path in sorted(root.glob("*.swift")):
        text = path.read_text()
        tests = len(TEST.findall(text))
        names = CLASS.findall(text)
        if tests and len(names) != 1:
            raise SystemExit(f"{path.name}: keep one test class per file to shard it")
        if tests:
            found[names[0]] = tests
    return found


def shards(found, count):
    bins = [[0, []] for _ in range(count)]
    for name, tests in sorted(found.items(), key=lambda item: (-item[1], item[0])):
        smallest = min(bins, key=lambda entry: entry[0])
        smallest[0] += tests
        smallest[1].append(name)
    return [sorted(names) for _, names in bins]


def main(argv):
    index, count = int(argv[1]), int(argv[2])
    if not 1 <= index <= count:
        raise SystemExit("index must be between 1 and count")
    print("\n".join(shards(test_classes(), count)[index - 1]))


if __name__ == "__main__":
    main(sys.argv)
