#!/usr/bin/env python3
"""Runs the ad-hoc TCC checks on a hosted VM. Usage: verify.py <build-dir> <output.json>"""
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RECEIVER_ID = "com.johnny4young.secreteo.spike.receiver"
TEXT = "secreteo ad-hoc delivery"


def launch_sender(build: Path, mode: str, *extra: str) -> dict:
    result_path = build / f"sender-{mode}-{time.monotonic_ns()}.json"
    subprocess.run(
        ["open", "-W", "-n", "-g", str(build / "SpikeSender.app"), "--args", mode, str(result_path), *extra],
        check=True,
        timeout=120,
    )
    return json.loads(result_path.read_text())


def main() -> None:
    build, output = Path(sys.argv[1]), Path(sys.argv[2])
    results: dict = {}

    results["before_grant"] = launch_sender(build, "probe")

    subprocess.run(
        ["sudo", "-E", "/usr/bin/python3", str(HERE / "grant.py"), str(build / "SpikeSender.app")], check=True)
    results["after_grant"] = launch_sender(build, "probe")

    record = build / "receiver-record.txt"
    subprocess.run(["open", "-n", str(build / "SpikeReceiver.app"), "--args", str(record)], check=True)
    deadline = time.monotonic() + 30
    while not record.exists() and time.monotonic() < deadline:
        time.sleep(0.2)
    results["delivery"] = launch_sender(build, "deliver", TEXT, RECEIVER_ID)
    time.sleep(1)
    results["received"] = record.read_text() if record.exists() else None
    subprocess.run(["pkill", "-x", "SpikeReceiver"], check=False)

    subprocess.run(["bash", str(HERE / "build.sh"), str(build), "two"], check=True)
    results["after_rebuild"] = launch_sender(build, "probe")

    checks = {
        "control_not_trusted_before_grant": results["before_grant"]["trusted"] is False,
        "trusted_after_grant": results["after_grant"]["trusted"] is True,
        "post_event_after_grant": results["after_grant"]["postEvent"] is True,
        "delivered_exactly_once": results["received"] == TEXT,
        "readback_matches": results["delivery"].get("readback") == TEXT,
        "other_cdhash_not_trusted": results["after_rebuild"]["trusted"] is False,
    }
    results["checks"] = checks
    output.write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))
    if not all(checks.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
