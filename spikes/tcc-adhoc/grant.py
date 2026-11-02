#!/usr/bin/env python3
"""Grants Accessibility and event posting to one ad-hoc app, only on a disposable hosted VM."""
import os
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DATABASE = "/Library/Application Support/com.apple.TCC/TCC.db"


def require_disposable_host() -> None:
    if not (
        os.environ.get("GITHUB_ACTIONS") == "true"
        and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
        and os.environ.get("SUDO_USER") == "runner"
        and os.environ.get("RUNNER_TEMP", "").startswith("/Users/runner/")
        and os.geteuid() == 0
    ):
        raise RuntimeError("Restricted to disposable hosted runners, as root")


def cdhash_requirement(application: Path) -> str:
    details = subprocess.check_output(["codesign", "-d", "-r-", str(application)], stderr=subprocess.STDOUT, text=True)
    lines = [line for line in details.splitlines() if "designated =>" in line]
    if len(lines) != 1:
        raise RuntimeError("Expected one designated requirement")
    requirement = lines[0].split("designated =>", 1)[1].strip()
    if not requirement.startswith('cdhash H"'):
        raise RuntimeError(f"Expected an ad-hoc cdhash requirement, got {requirement}")
    return requirement


def main() -> None:
    require_disposable_host()
    application = Path(sys.argv[1]).resolve()
    with (application / "Contents/Info.plist").open("rb") as handle:
        identifier = plistlib.load(handle)["CFBundleIdentifier"]
    with tempfile.TemporaryDirectory(dir=os.environ["RUNNER_TEMP"]) as temporary:
        blob = Path(temporary) / "requirement.bin"
        subprocess.run(["csreq", "-r", "=" + cdhash_requirement(application), "-b", str(blob)], check=True)
        requirement = blob.read_bytes()
    with sqlite3.connect(f"file:{DATABASE}?mode=rw", uri=True) as connection:
        for service in ("kTCCServiceAccessibility", "kTCCServicePostEvent"):
            connection.execute(
                """INSERT OR REPLACE INTO access
                   (service, client, client_type, auth_value, auth_reason, auth_version,
                    csreq, indirect_object_identifier, flags, last_modified)
                   VALUES (?, ?, 0, 2, 4, 1, ?, 'UNUSED', 0, ?)""",
                (service, identifier, requirement, int(time.time())),
            )
    print(f"Granted {identifier}")


if __name__ == "__main__":
    main()
