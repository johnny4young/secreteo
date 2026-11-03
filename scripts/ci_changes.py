#!/usr/bin/env python3
"""Classifies a change for CI. Prints `code=` and `delivery=` lines for GITHUB_OUTPUT.

Usage: ci_changes.py [path ...], or paths on stdin. An empty list counts as code,
so a failed diff can never skip a job.
"""
import fnmatch
import sys

DOCS_ONLY = ("docs/*", "*.md", "LICENSE", "site/*", ".github/ISSUE_TEMPLATE/*")
DELIVERY = ("Sources/Delivery/*", "Sources/Triggers/*", "Tests/DeliveryTests/*", "Tests/TriggersTests/*",
            ".github/workflows/ci.yml", "scripts/ci_changes.py", "scripts/ci_gate.py")


def matches(path: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def classify(paths: list[str]) -> dict[str, bool]:
    if not paths:
        return {"code": True, "delivery": True}
    return {
        "code": not all(matches(path, DOCS_ONLY) for path in paths),
        "delivery": any(matches(path, DELIVERY) for path in paths),
    }


def main() -> None:
    paths = sys.argv[1:] or [line.strip() for line in sys.stdin if line.strip()]
    for name, value in classify(paths).items():
        print(f"{name}={'true' if value else 'false'}")


if __name__ == "__main__":
    main()
