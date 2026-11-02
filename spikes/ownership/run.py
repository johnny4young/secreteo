#!/usr/bin/env python3
"""Runs the ownership lock scenarios against scratch roots and scratch preference domains.

Usage: run.py <output.json>
"""
import hashlib
import json
import random
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = "com.johnny4young.secreteo"
DEV = "com.johnny4young.secreteo.dev"
THIRD = "com.johnny4young.bridge"
PREFERENCES = Path.home() / "Library/Preferences"


class Lab:
    def __init__(self, work: Path) -> None:
        self.work = work
        self.client = work / "client"
        subprocess.run(
            ["swiftc", "-O", "-swift-version", "6", str(HERE / "client.swift"), "-o", str(self.client)],
            check=True,
        )

    def root(self, owner: str) -> tuple[Path, Path]:
        root = self.work / uuid.uuid4().hex
        self.call("init", "--root", str(root), "--app", owner)
        return root, root / "events.log"

    def call(self, *args: str) -> str:
        return subprocess.run([str(self.client), *args], check=True, capture_output=True, text=True).stdout.strip()

    def spawn(self, *args: str) -> subprocess.Popen:
        return subprocess.Popen([str(self.client), *args], stdout=subprocess.PIPE, text=True)


def check_log(log: Path) -> dict:
    """Replays events in file order and counts every protocol violation."""
    open_session = None
    enters = overlaps = refusals = handoffs_inside = bad_generation = 0
    generation_of = {}
    highest = 1
    gaps = 0
    if not log.exists():
        return {"enters": 0, "overlaps": 0, "refused": 0, "handoffs_inside": 0, "bad_generation": 0, "gaps": 0}
    for line in log.read_text().splitlines():
        kind, *rest = line.split()
        if kind == "refused":
            refusals += 1
        elif kind == "enter":
            app, pid, generation = rest
            enters += 1
            if open_session is not None:
                overlaps += 1
            open_session = (app, pid)
            if int(generation) != highest:
                bad_generation += 1
        elif kind == "exit":
            app, pid, _ = rest
            if open_session != (app, pid):
                overlaps += 1
            open_session = None
        elif kind == "handoff":
            _, _, generation = rest
            if open_session is not None:
                handoffs_inside += 1
            if int(generation) != highest + 1:
                gaps += 1
            highest = int(generation)
            generation_of[int(generation)] = rest[0]
    return {
        "enters": enters,
        "overlaps": overlaps,
        "refused": refusals,
        "handoffs_inside": handoffs_inside,
        "bad_generation": bad_generation,
        "gaps": gaps,
        "final_generation": highest,
    }


def wait_all(processes: list[subprocess.Popen]) -> None:
    for process in processes:
        process.communicate(timeout=300)
        assert process.returncode == 0


def start_time() -> str:
    return str(time.clock_gettime_ns(time.CLOCK_UPTIME_RAW) + 500_000_000)


def simultaneous(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    start = start_time()
    processes = [
        lab.spawn("sessions", "--root", str(root), "--app", app, "--rounds", "2000",
                  "--log", str(log), "--start-at", start, "--hold-us", "50")
        for app in (RELEASE, DEV, THIRD)
    ]
    wait_all(processes)
    return check_log(log)


def toggle(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    sessions = [
        lab.spawn("sessions", "--root", str(root), "--app", app, "--rounds", "4000",
                  "--log", str(log), "--hold-us", "100")
        for app in (RELEASE, THIRD)
    ]
    for index in range(500):
        target = THIRD if index % 2 == 0 else RELEASE
        lab.call("handoff", "--root", str(root), "--to", target, "--log", str(log))
    wait_all(sessions)
    return check_log(log)


def stale_read(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    # The delay sits between the unlocked read and the lock, where handoffs land.
    sessions = [
        lab.spawn("sessions", "--root", str(root), "--app", app, "--rounds", "2000",
                  "--log", str(log), "--hold-us", "50", "--stale-us", "200")
        for app in (RELEASE, THIRD)
    ]
    for index in range(500):
        target = THIRD if index % 2 == 0 else RELEASE
        lab.call("handoff", "--root", str(root), "--to", target, "--log", str(log))
    wait_all(sessions)
    return check_log(log)


def crash(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    lock_ms = []
    wrongly_admitted = owner_changed = recovery_failed = 0
    for _ in range(200):
        holder = lab.spawn("hold", "--root", str(root), "--app", RELEASE, "--log", str(log))
        assert holder.stdout.readline().strip() == "held"
        time.sleep(random.uniform(0, 0.02))
        holder.send_signal(signal.SIGKILL)
        holder.wait()
        # A killed session never logs exit, so the checker sees only clean sessions.
        result = json.loads(lab.call("try-admit", "--root", str(root), "--app", THIRD))
        lock_ms.append(result["lock_ms"])
        wrongly_admitted += int(result["admitted"])
        owner_changed += int(result["owner"] != RELEASE)
        lab.call("handoff", "--root", str(root), "--to", THIRD)
        recovered = json.loads(lab.call("try-admit", "--root", str(root), "--app", THIRD))
        recovery_failed += int(not recovered["admitted"])
        lab.call("handoff", "--root", str(root), "--to", RELEASE)
    ordered = sorted(lock_ms)
    return {
        "crashes": 200,
        "lock_ms_p50": round(statistics.median(ordered), 2),
        "lock_ms_p99": round(ordered[int(len(ordered) * 0.99) - 1], 2),
        "lock_ms_max": round(ordered[-1], 2),
        "wrongly_admitted": wrongly_admitted,
        "owner_changed": owner_changed,
        "recovery_failed": recovery_failed,
    }


def mid_session(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    blocked_then_applied = 0
    for index in range(200):
        target = THIRD if index % 2 == 0 else RELEASE
        owner = RELEASE if index % 2 == 0 else THIRD
        holder = lab.spawn("hold", "--root", str(root), "--app", owner, "--log", str(log), "--hold-ms", "20")
        assert holder.stdout.readline().strip() == "held"
        outcome = json.loads(lab.call("handoff", "--root", str(root), "--to", target, "--log", str(log)))
        blocked_then_applied += int(outcome["outcome"] == "changed")
        holder.communicate()
    result = check_log(log)
    result["applied_after_session"] = blocked_then_applied

    root, log = lab.root(RELEASE)
    holder = lab.spawn("hold", "--root", str(root), "--app", RELEASE, "--log", str(log), "--hold-ms", "500")
    assert holder.stdout.readline().strip() == "held"
    outcome = json.loads(lab.call("handoff", "--root", str(root), "--to", THIRD, "--log", str(log), "--timeout-ms", "50"))
    holder.communicate()
    state = json.loads((root / "ownership.json").read_text())
    result["timeout_outcome"] = outcome["outcome"]
    result["timeout_owner_unchanged"] = state == {"owner": RELEASE, "generation": 1}
    return result


def competing(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    drivers = [
        lab.spawn("handoff", "--root", str(root), "--to", target, "--log", str(log), "--rounds", "500")
        for target in (THIRD, RELEASE)
    ]
    wait_all(drivers)
    result = check_log(log)
    result["expected_final_generation"] = 1001
    return result


def plist_digest(domain: str) -> str | None:
    path = PREFERENCES / f"{domain}.plist"
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def discovery(lab: Lab) -> dict:
    token = uuid.uuid4().hex[:8]
    domain = f"com.johnny4young.secreteo.spike.{token}.writer"
    missing = f"com.johnny4young.secreteo.spike.{token}.missing"
    latencies = []
    try:
        lab.call("pref-write", "--domain", domain, "--value", "first")
        time.sleep(0.5)
        before = plist_digest(domain)
        reads = [lab.call("pref-read", "--domain", domain) for _ in range(50)]
        time.sleep(0.5)
        after = plist_digest(domain)
        missing_read = lab.call("pref-read", "--domain", missing)
        time.sleep(0.5)

        timeouts = 0
        for index in range(30):
            value = f"v{index}"
            watcher = lab.spawn("pref-watch", "--domain", domain, "--value", value)
            assert watcher.stdout.readline().strip() == "ready"
            written = int(lab.call("pref-write", "--domain", domain, "--value", value))
            seen = watcher.communicate(timeout=20)[0].strip()
            if seen == "timeout":
                timeouts += 1
            else:
                latencies.append((int(seen) - written) / 1_000_000)
        ordered = sorted(latencies)
        return {
            "reader_saw_value": set(reads) == {"first"},
            "plist_unchanged_by_reader": before is not None and before == after,
            "missing_read": missing_read,
            "missing_plist_created": (PREFERENCES / f"{missing}.plist").exists(),
            "samples": len(latencies),
            "timeouts": timeouts,
            "staleness_ms_p50": round(statistics.median(ordered), 2) if ordered else None,
            "staleness_ms_max": round(ordered[-1], 2) if ordered else None,
        }
    finally:
        for name in (domain, missing):
            subprocess.run(["defaults", "delete", name], capture_output=True)
            (PREFERENCES / f"{name}.plist").unlink(missing_ok=True)


def dev_and_release(lab: Lab) -> dict:
    root, log = lab.root(RELEASE)
    refused = wrongly_admitted = 0
    for _ in range(100):
        outcome = json.loads(lab.call("handoff", "--root", str(root), "--to", DEV, "--log", str(log)))
        refused += int(outcome["outcome"] == "refused")
        wrongly_admitted += int(json.loads(lab.call("try-admit", "--root", str(root), "--app", DEV))["admitted"])
    confirmed = json.loads(
        lab.call("handoff", "--root", str(root), "--to", DEV, "--log", str(log), "--user-confirmed"))
    admitted = json.loads(lab.call("try-admit", "--root", str(root), "--app", DEV, "--log", str(log)))
    return {
        "attempts": 100,
        "refused": refused,
        "wrongly_admitted": wrongly_admitted,
        "confirmed_outcome": confirmed["outcome"],
        "admitted_after_confirmation": admitted["admitted"],
        "log": check_log(log),
    }


def negative_control(lab: Lab) -> dict:
    # Both clients claim the same owner so only the lock could keep them apart.
    root, log = lab.root(RELEASE)
    start = start_time()
    processes = [
        lab.spawn("sessions", "--root", str(root), "--app", RELEASE, "--rounds", "2000",
                  "--log", str(log), "--start-at", start, "--hold-us", "50", "--no-lock")
        for _ in range(3)
    ]
    wait_all(processes)
    return check_log(log)


def main() -> None:
    output = Path(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="secreteo-ownership-") as work:
        lab = Lab(Path(work))
        results = {}
        for name, scenario in [
            ("negative_control", negative_control),
            ("simultaneous", simultaneous),
            ("toggle", toggle),
            ("stale_read", stale_read),
            ("crash", crash),
            ("mid_session", mid_session),
            ("competing", competing),
            ("discovery", discovery),
            ("dev_and_release", dev_and_release),
        ]:
            started = time.monotonic()
            results[name] = scenario(lab)
            results[name]["seconds"] = round(time.monotonic() - started, 1)
            print(name, json.dumps(results[name]), flush=True)
        output.write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
