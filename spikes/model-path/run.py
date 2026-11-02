#!/usr/bin/env python3
"""Measures .noindex behavior and Core ML specialization under a throwaway root.

Usage: run.py <source-models-dir> <output.json>
The source directory is only cloned from, never written to.
"""
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
SUPPORT = Path.home() / "Library/Application Support"
CACHES = Path.home() / "Library/Caches"
IDENTITIES = ["secreteo-spike-specialize-a", "secreteo-spike-specialize-b"]
CONTROL_LIMIT = 600
NOINDEX_WINDOW = 300


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def build(bin_dir: Path) -> dict[str, Path]:
    binaries = {}
    for identity in IDENTITIES:
        binaries[identity] = bin_dir / identity
        run("swiftc", "-O", str(HERE / "specialize.swift"), "-o", str(binaries[identity]))
    return binaries


def clone_read_only(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    run("cp", "-cR", str(source), str(target))
    run("chmod", "-R", "a-w", str(target))


def load(binary: Path, model_dir: Path, kind: str) -> dict[str, float]:
    return json.loads(run(str(binary), str(model_dir), kind))


def summary(samples: list[dict[str, float]]) -> dict[str, float]:
    totals = sorted(sample["total"] for sample in samples)
    return {
        "n": len(totals),
        "p50_ms": round(statistics.median(totals), 1),
        "max_ms": round(totals[-1], 1),
        "min_ms": round(totals[0], 1),
    }


def spotlight(root: Path) -> dict:
    token = "secreteospike" + uuid.uuid4().hex
    control = root / "control"
    hidden = root / "v1.noindex/models/x/payload"
    for directory in (control, hidden):
        directory.mkdir(parents=True)
        (directory / "merges.txt").write_text(f"{token}\n")
        (directory / "config.json").write_text(json.dumps({"token": token}))

    found = lambda path: [line for line in run("mdfind", "-onlyin", str(path), token).splitlines() if line]
    started = time.monotonic()
    control_after = None
    while time.monotonic() - started < CONTROL_LIMIT:
        if found(control):
            control_after = round(time.monotonic() - started, 1)
            break
        time.sleep(5)
    if control_after is None:
        return {"verdict": "inconclusive", "control_found_after_s": None}

    deadline = time.monotonic() + NOINDEX_WINDOW
    while time.monotonic() < deadline:
        leaked = found(root / "v1.noindex")
        if leaked:
            return {"verdict": "fail", "control_found_after_s": control_after, "leaked": len(leaked)}
        time.sleep(10)
    return {
        "verdict": "pass",
        "control_found_after_s": control_after,
        "noindex_window_s": NOINDEX_WINDOW,
        "control_hits": len(found(control)),
    }


def time_machine(root: Path) -> dict:
    swift = (
        "import Foundation; var url = URL(fileURLWithPath: CommandLine.arguments[1]); "
        "var values = URLResourceValues(); values.isExcludedFromBackup = true; "
        "try url.setResourceValues(values)"
    )
    with tempfile.TemporaryDirectory() as scratch:
        tool = Path(scratch) / "exclude.swift"
        tool.write_text(swift)
        run("swift", str(tool), str(root))
    nested = root / "v1.noindex/models/x/payload/merges.txt"
    answer = run("tmutil", "isexcluded", str(nested))
    return {"verdict": "pass" if "[Excluded]" in answer else "fail", "answer": answer.split()[0]}


def specialization(root: Path, source: Path, binaries: dict[str, Path]) -> dict:
    parakeet = source / "parakeet-tdt-0.6b-v3"
    silero = source / "silero-vad-coreml"
    first, second = IDENTITIES
    bases = {"noindex": root / "v1.noindex/models", "plain": root / "plain/models"}
    cold: dict[str, list] = {"noindex": [], "plain": []}
    warm = []

    for index in range(5):
        order = ["noindex", "plain"] if index % 2 == 0 else ["plain", "noindex"]
        for kind in order:
            target = bases[kind] / f"cold-{index}"
            clone_read_only(parakeet, target)
            cold[kind].append(load(binaries[first], target, "parakeet"))

    warm_target = bases["noindex"] / "cold-0"
    for _ in range(5):
        warm.append(load(binaries[first], warm_target, "parakeet"))

    second_identity = []
    for index in range(3):
        target = bases["noindex"] / f"identity-{index}"
        clone_read_only(parakeet, target)
        load(binaries[first], target, "parakeet")
        second_identity.append(load(binaries[second], target, "parakeet"))

    silero_cold = []
    for index in range(5):
        target = bases["noindex"] / f"silero-{index}"
        clone_read_only(silero, target)
        silero_cold.append(load(binaries[first], target, "silero"))

    return {
        "parakeet_cold_noindex": summary(cold["noindex"]),
        "parakeet_cold_plain": summary(cold["plain"]),
        "parakeet_warm": summary(warm),
        "parakeet_second_identity": summary(second_identity),
        "silero_cold": summary(silero_cold),
        "encoder_cold_noindex_ms": [round(sample["Encoder.mlmodelc"], 1) for sample in cold["noindex"]],
        "raw": {
            "cold": cold,
            "warm": warm,
            "second_identity": second_identity,
        },
    }


def remove_read_only(path: Path) -> None:
    if path.exists():
        subprocess.run(["chmod", "-R", "u+w", str(path)], check=False)
        shutil.rmtree(path)


def main() -> None:
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    root = SUPPORT / f"com.johnny4young.local-models-spike-{uuid.uuid4().hex[:8]}"
    root.mkdir()
    bin_dir = Path(tempfile.mkdtemp(prefix="secreteo-spike-"))
    try:
        binaries = build(bin_dir)
        result = {
            "chip": run("sysctl", "-n", "machdep.cpu.brand_string"),
            "macos": run("sw_vers", "-productVersion"),
            "load_before": run("uptime"),
            "spotlight": spotlight(root),
        }
        result["time_machine"] = time_machine(root)
        result["specialization"] = specialization(root, source, binaries)
        result["load_after"] = run("uptime")
        output.write_text(json.dumps(result, indent=2))
    finally:
        remove_read_only(root)
        shutil.rmtree(bin_dir, ignore_errors=True)
        for identity in IDENTITIES:
            remove_read_only(CACHES / identity)


if __name__ == "__main__":
    main()
