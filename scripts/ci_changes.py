#!/usr/bin/env python3
"""Classifies a change for CI. Prints `code=`, `delivery=` and `release=` lines for GITHUB_OUTPUT.

Usage: ci_changes.py [path ...], or paths on stdin. An empty list counts as code,
so a failed diff can never skip a job.
"""
import fnmatch
import sys

DOCS_ONLY = ("docs/*", "*.md", "LICENSE", "site/*", ".github/ISSUE_TEMPLATE/*")
DELIVERY = ("Sources/Delivery/*", "Sources/Triggers/*", "Tests/DeliveryTests/*", "Tests/TriggersTests/*",
            "spikes/tcc-adhoc/*", "scripts/run-signed-handoff.sh",
            ".github/workflows/ci.yml", "scripts/ci_changes.py", "scripts/ci_gate.py")
RELEASE = ("scripts/package-release.sh", "scripts/sign-app.sh", "scripts/release-dryrun.sh",
           "scripts/generate-appcast.sh", "scripts/verify_release.py", "scripts/verify_appcast.py",
           "scripts/verify-ed-signature.swift", "scripts/smoke-launch.sh", "scripts/fetch-sparkle.sh", "scripts/throwaway-sparkle-key.swift",
           "project.yml", "Apps/Secreteo/Info.plist", "Apps/Secreteo/Secreteo.entitlements",
           "Apps/Secreteo/SecreteoMain.swift", "Apps/Secreteo/SparkleUpdater.swift",
           ".github/workflows/ci.yml", "scripts/ci_changes.py", "scripts/ci_gate.py")


def matches(path: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def classify(paths: list[str]) -> dict[str, bool]:
    if not paths:
        return {"code": True, "delivery": True, "release": True}
    return {
        "code": not all(matches(path, DOCS_ONLY) for path in paths),
        "delivery": any(matches(path, DELIVERY) for path in paths),
        "release": any(matches(path, RELEASE) for path in paths),
    }


def main() -> None:
    paths = sys.argv[1:] or [line.strip() for line in sys.stdin if line.strip()]
    for name, value in classify(paths).items():
        print(f"{name}={'true' if value else 'false'}")


if __name__ == "__main__":
    main()
