#!/usr/bin/env python3
"""Refuses a release artifact that would not ship correctly.

Usage: verify_release.py <app> <dmg> <version> <production|dryrun>
"""
import base64
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.johnny4young.secreteo"
FEED = "https://github.com/johnny4young/secreteo/releases/latest/download/appcast.xml"
FORBIDDEN_PAYLOAD = (".dSYM", ".debug.dylib", "__preview.dylib", ".xctest", ".swiftmodule", "generate_appcast",
                     "sign_update", "generate_keys")


def info_problems(info: dict, version: str) -> list[str]:
    expected = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "LSMinimumSystemVersion": "26.0",
        "LSUIElement": True,
        "SUFeedURL": FEED,
        "SUEnableAutomaticChecks": True,
    }
    problems = [f"{key} is {info.get(key)!r}, expected {value!r}"
                for key, value in expected.items() if info.get(key) != value]
    try:
        key_length = len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True))
    except ValueError:
        key_length = 0
    if key_length != 32:
        problems.append("SUPublicEDKey is not a 32-byte EdDSA key")
    return problems


def payload_problems(relative_paths: list[str], sparkle_version: str, pinned_sparkle: str) -> list[str]:
    problems = [f"{path} must not ship" for path in relative_paths
                if any(marker in path for marker in FORBIDDEN_PAYLOAD)]
    frameworks = {path.split("/")[2] for path in relative_paths
                  if path.startswith("Contents/Frameworks/") and path.count("/") >= 2}
    if frameworks != {"Sparkle.framework"}:
        problems.append(f"unexpected frameworks: {sorted(frameworks)}")
    if "Contents/Resources/THIRD-PARTY-NOTICES.md" not in relative_paths:
        problems.append("THIRD-PARTY-NOTICES.md is missing")
    if sparkle_version != pinned_sparkle:
        problems.append(f"Sparkle is {sparkle_version}, pinned {pinned_sparkle}")
    return problems


def signature_problems(name: str, details: str, entitlements: str, mode: str) -> list[str]:
    problems = []
    if "get-task-allow" in entitlements:
        problems.append(f"{name} carries get-task-allow, which notarization rejects")
    if mode == "production":
        if not re.search(r"^CodeDirectory .*flags=.*runtime", details, re.MULTILINE):
            problems.append(f"{name} has no hardened runtime")
        if "Authority=Developer ID Application:" not in details:
            problems.append(f"{name} is not signed with Developer ID")
        if not re.search(r"^Timestamp=", details, re.MULTILINE):
            problems.append(f"{name} has no secure timestamp")
    elif "Signature=adhoc" not in details:
        problems.append(f"{name} is not ad-hoc signed")
    return problems


def run(*command: str) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, check=False)


def main() -> None:
    app, dmg, version, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
    contents = app / "Contents"
    sparkle = contents / "Frameworks/Sparkle.framework"
    current = sparkle / "Versions/Current"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    sparkle_info = plistlib.loads((current / "Resources/Info.plist").read_bytes())
    pinned = re.search(r'SPARKLE_VERSION:-([0-9.]+)', (ROOT / "scripts/fetch-sparkle.sh").read_text()).group(1)
    paths = [str(path.relative_to(app)) for path in app.rglob("*")]

    problems = info_problems(info, version)
    problems += payload_problems(paths, sparkle_info.get("CFBundleShortVersionString", ""), pinned)

    archs = run("lipo", "-archs", str(contents / "MacOS/Secreteo")).stdout.split()
    if archs != ["arm64"]:
        problems.append(f"architectures are {archs}, expected arm64")

    verified = run("codesign", "--verify", "--deep", "--strict", str(app))
    if verified.returncode != 0:
        problems.append(f"codesign rejected the app: {verified.stderr.strip()}")

    nested = [current / "XPCServices/Installer.xpc", current / "XPCServices/Downloader.xpc",
              current / "Autoupdate", current / "Updater.app", sparkle, app]
    for item in nested:
        details = run("codesign", "-dvv", str(item)).stderr
        entitlements = run("codesign", "-d", "--entitlements", ":-", str(item)).stdout
        problems += signature_problems(item.name, details, entitlements, mode)

    if mode == "production":
        checks = [("xcrun", "stapler", "validate", str(app)), ("xcrun", "stapler", "validate", str(dmg)),
                  ("spctl", "-a", "-t", "exec", "-vv", str(app)),
                  ("spctl", "-a", "-t", "open", "--context", "context:primary-signature", "-vv", str(dmg))]
        for check in checks:
            result = run(*check)
            if result.returncode != 0:
                problems.append(f"{' '.join(check)}: {result.stderr.strip() or result.stdout.strip()}")

    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        sys.exit(1)
    print(f"Verified {app.name} {version} and {dmg.name} ({mode})")


if __name__ == "__main__":
    main()
