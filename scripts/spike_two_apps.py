#!/usr/bin/env python3
"""Spike 1 harness: does running Secreteo and Portavoz together degrade either one?

`plan` prints the cells and an estimate, `run` drives both apps (or a simulated pair with
--dry-run) and appends one row per trial, `report` scores the rows against the thresholds
in docs/spikes/two-apps-at-once.md. Rows hold times and counts only, never audio or words.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import random
import re
import shutil
import signal
import subprocess
import sys
import time

sys.path.append(str(Path(__file__).resolve().parent))  # after the standard library: -I leaves this folder out

import dictation_corpus as corpus

ROOT = Path(__file__).resolve().parent.parent
AGENT_SOURCE = Path(__file__).resolve().with_name("spike-agent.swift")

# Written before measuring (docs/spikes/two-apps-at-once.md). Never loosen these.
CAPTION_RISE_LIMIT = 0.5
FIRST_TEXT_RATIO_LIMIT = 1.5
FIRST_TEXT_CEILING = 2.5
MINIMUM_TRIALS = 30
# The owner runs the Bluetooth and sleep cells by hand, this many times each (decision of 2026-11-12).
MANUAL_TRIALS = 5

APPS = ("secreteo", "portavoz")
MODELS = ("parakeet", "parakeetUltra")
STATES = ("cold", "warm")
ENDINGS = ("stop", "cancel")
EVENTS = ("bluetooth", "sleep")
SHIPPED_SECRETEO = "com.johnny4young.secreteo"
OWNERSHIP_FILE = Path("~/Library/Application Support/com.johnny4young.dictation-ownership/ownership.json")

LEAD_SECONDS = 0.5
SETTLE_QUIET = 1.5
SETTLE_CAP = 6.0
DELIVERY_CAP = 20.0
QUIET_WINDOW = 2.0
BURST_SECONDS = 0.05
# Cancel once text shows, so a cancelled trial still times its first text.
CANCEL_AFTER_TEXT = 0.5
CANCEL_CAP = 6.0


class SpikeError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SpikeError(message)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


# MARK: Plan

def cell_id(cell):
    parts = [cell["dictating"], "both" if cell["companion"] else "alone", cell["modelState"], cell["model"],
             cell["background"]]
    if cell["microphone"]:
        parts.append(cell["microphone"] + "-input")
    parts.append(cell["ending"])
    if cell["event"]:
        parts.append(cell["event"])
    return "-".join(parts)


def build_cells(trials=MINIMUM_TRIALS, manual_trials=MANUAL_TRIALS):
    """Every automated cell has a control: the same app, model state, model and ending, alone and idle."""
    cells = []
    for dictating in APPS:
        for state in STATES:
            for model in MODELS:
                for ending in ENDINGS:
                    base = {"dictating": dictating, "modelState": state, "model": model, "ending": ending,
                            "event": None, "manual": False, "trials": trials}
                    control = {**base, "companion": False, "background": "idle", "microphone": None, "control": None}
                    control["id"] = cell_id(control)
                    cells.append(control)
                    # Only Secreteo can dictate beside a Portavoz meeting; the other app's microphone matters only then.
                    variants = [("idle", None)]
                    if dictating == "secreteo":
                        variants += [("meeting", "same"), ("meeting", "different")]
                    for background, microphone in variants:
                        treatment = {**base, "companion": True, "background": background,
                                     "microphone": microphone, "control": control["id"]}
                        treatment["id"] = cell_id(treatment)
                        cells.append(treatment)
    for dictating in APPS:
        for event in EVENTS:
            base = {"dictating": dictating, "modelState": "warm", "model": "parakeetUltra", "ending": "stop"}
            control = cell_id({**base, "companion": False, "background": "idle", "microphone": None, "event": None})
            cell = {**base, "companion": True, "background": "idle", "microphone": None, "event": event,
                    "manual": True, "trials": manual_trials, "control": control}
            cell["id"] = cell_id(cell)
            cells.append(cell)
    return cells


def schedule(cells, block=10):
    """Blocks of trials, grouped by the app that dictates, in ABC CBA order so drift hits every cell alike."""
    require(block >= 1, "block size must be positive")
    blocks = []
    for dictating in APPS:
        group = [cell for cell in cells if cell["dictating"] == dictating and not cell["manual"]]
        rounds = max((math.ceil(cell["trials"] / block) for cell in group), default=0)
        for index in range(rounds):
            for cell in group if index % 2 == 0 else list(reversed(group)):
                first = index * block
                last = min(first + block, cell["trials"])
                if first < last:
                    order = list(APPS) if len(blocks) % 2 == 0 else list(reversed(APPS))
                    blocks.append({"cell": cell["id"], "trials": list(range(first, last)), "launchOrder": order})
    for cell in cells:
        if cell["manual"]:
            blocks.append({"cell": cell["id"], "trials": list(range(cell["trials"])), "launchOrder": list(APPS)})
    return blocks


def estimate_seconds(cells, blocks, mean_audio=4.1):
    by_id = {cell["id"]: cell for cell in cells}
    total = 0.0
    for block in blocks:
        cell = by_id[block["cell"]]
        trial = LEAD_SECONDS + mean_audio + QUIET_WINDOW + 1.0
        if cell["ending"] == "stop":
            trial += SETTLE_QUIET + 1.5
        if cell["modelState"] == "cold":
            trial += 9.0
        setup = 20.0 + (trial if cell["modelState"] == "warm" else 0)
        total += setup + trial * len(block["trials"])
    return total


# MARK: Corpus

def corpus_cases(audio_root=None):
    """English and Spanish speech, clean profile: the same sequence for every cell."""
    _, cells = corpus.read_public_corpus()
    frames = {}
    if audio_root is not None:
        manifest, _ = corpus.read_json(audio_root / "manifest.json")
        corpus.validate_audio_manifest(manifest, cells, audio_root)
        frames = {entry["caseID"]: entry["frames"] for entry in manifest["entries"]}
    cases = []
    for case_id, (family, profile) in sorted(cells.items()):
        if family["audioKind"] != "speech" or profile["id"] != "clean" or family["cohort"] not in ("en", "es"):
            continue
        words = sum(len(segment["text"].split()) for segment in family["segments"])
        # Without rendered audio, a dry run estimates duration from the profile's speaking rate.
        seconds = frames[case_id] / 16_000 if case_id in frames else words * 60 / profile["wordsPerMinute"] + 0.25
        cases.append({"caseID": case_id, "expectedWords": words, "seconds": seconds,
                      "speechSeconds": seconds - profile["tailMilliseconds"] / 1_000,
                      "path": str(audio_root / (case_id + ".wav")) if audio_root else None})
    require(cases, "no speech cases in the corpus")
    return cases


# MARK: Measures

def nearest_rank(values, fraction=0.95):
    ordered = sorted(values)
    if not ordered:
        return None
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def delivery_bursts(insertions):
    bursts = []
    for event in sorted(insertions, key=lambda item: item["t"]):
        if bursts and event["t"] - bursts[-1]["end"] <= BURST_SECONDS:
            bursts[-1]["end"] = event["t"]
            bursts[-1]["words"] += event["words"]
        else:
            bursts.append({"start": event["t"], "end": event["t"], "words": event["words"]})
    return bursts


def matching_timing(records, trigger):
    candidates = [record for record in records if trigger - 0.5 <= record["startedAt"] <= trigger + 5]
    return min(candidates, key=lambda record: abs(record["startedAt"] - trigger)) if candidates else None




def measure(observation, cell, case):
    """Turns one trial's raw observations into the row's measures. None means never seen."""
    trigger = observation["triggerAt"]
    samples = sorted(observation.get("panel", []), key=lambda sample: sample["t"])
    first_text = next((sample["t"] for sample in samples if sample["words"] > 0), None)
    row = {"timeToFirstText": None if first_text is None else first_text - trigger,
           "captionLatency": None, "captionCensored": False,
           "panelSeen": any(sample.get("panel") for sample in samples)}
    if cell["ending"] == "stop" and cell["event"] != "sleep" and observation.get("stopAt") is not None:
        speech_end = observation["playbackStartedAt"] + case["speechSeconds"]
        last_change, previous = None, 0
        for sample in samples:
            if sample["t"] > observation["stopAt"]:
                break
            if sample.get("revision", 0) != previous:
                last_change, previous = sample["t"], sample.get("revision", 0)
        if last_change is not None and first_text is not None:
            row["captionLatency"] = max(0.0, last_change - speech_end)
            row["captionCensored"] = not observation.get("settled", True)
    bursts = delivery_bursts(observation.get("insertions", []))
    row["deliveries"] = len(bursts)
    row["deliveredWords"] = sum(burst["words"] for burst in bursts)
    row["expectedWords"] = case["expectedWords"]
    row["doubleDelivery"] = len(bursts) > 1
    row["deliveredAfterCancel"] = cell["ending"] == "cancel" and bool(bursts)
    row["missingDelivery"] = cell["ending"] == "stop" and cell["event"] != "sleep" and not bursts
    timing = matching_timing(observation.get("timing", []), trigger) if cell["dictating"] == "secreteo" else None
    row["timingSeen"] = timing is not None
    row["lostFrames"] = None
    row["appFirstCaption"] = None
    row["appOutcome"] = None
    row["engine"] = None
    if timing is not None:
        audio = timing["audio"]
        if audio.get("paddingFrames") is not None and audio.get("rejectedFrames") is not None:
            row["lostFrames"] = audio["paddingFrames"] + audio["rejectedFrames"] + audio["relayDroppedFrames"]
        caption = timing["session"]["elapsedSeconds"].get("firstCaptionHandled")
        if caption is not None:
            row["appFirstCaption"] = timing["startedAt"] - trigger + caption
        row["appOutcome"] = timing["session"]["outcome"]
        row["engine"] = timing["engine"]
    row["crashes"] = sorted(observation.get("crashes", []))
    alive = {**observation.get("aliveAtStart", {}), **observation.get("alive", {})}
    row["crashed"] = (bool(row["crashes"]) or not all(observation.get("alive", {}).values())
                      or not all(observation.get("aliveAtStart", {}).values()))
    row["alive"] = alive
    row["resources"] = observation.get("resources", {})
    return row


def trial_problem(row, cell):
    """A trial that measured nothing usable: it becomes an error row, and three in a row stop the run."""
    if not row["panelSeen"] and cell["event"] != "sleep" and not row["crashed"]:
        return "the dictation panel never appeared: is the app the owner, with dictation on?"
    if cell["dictating"] == "secreteo" and not row["timingSeen"] and not row["crashed"]:
        return "no timing log line: the harness must launch the Dev build itself"
    if row["engine"] not in (None, cell["model"]):
        return f"{row['engine']} ran instead of {cell['model']}: download that model in the app"
    return None


# MARK: Report

NEVER = "never"


def p95_or_never(values):
    value = nearest_rank(values)
    return NEVER if value == math.inf else value


def summarize(rows, cell):
    counted = [row for row in rows if row["cell"] == cell["id"] and not row.get("warmup")
               and not row.get("error") and not row.get("lateCrash")]
    timed = cell["event"] != "sleep"
    # A dictation that never showed text, or never settled, is slower than any that did.
    first_text = [math.inf if row["timeToFirstText"] is None else row["timeToFirstText"]
                  for row in counted if timed]
    captions = [math.inf if row["captionLatency"] is None else row["captionLatency"]
                for row in counted if timed and cell["ending"] == "stop"]
    lost = [row["lostFrames"] for row in counted]
    late = sum(1 for row in rows if row["cell"] == cell["id"] and row.get("lateCrash"))
    return {
        "trials": len(counted),
        "errors": sum(1 for row in rows if row["cell"] == cell["id"] and row.get("error")),
        "timeToFirstTextP95": p95_or_never(first_text),
        "captionLatencyP95": p95_or_never(captions),
        "captionCensored": sum(1 for row in counted if row["captionCensored"]),
        "lostFrames": None if not counted or any(value is None for value in lost) else sum(lost),
        "missingDeliveries": sum(1 for row in counted if row["missingDelivery"]),
        "doubleDeliveries": sum(1 for row in counted if row["doubleDelivery"]),
        "deliveredAfterCancel": sum(1 for row in counted if row["deliveredAfterCancel"]),
        "crashes": sum(1 for row in counted if row["crashed"]) + late,
        "peakFootprint": {app: max((row["resources"].get("footprint", {}).get(app, 0) for row in counted),
                                   default=0) for app in APPS},
    }


def check(name, passed, detail):
    return {"check": name, "result": "pass" if passed is True else "fail" if passed is False else "missing",
            "detail": detail}


def zero_count(value, enough):
    """Any occurrence fails at once; a clean count passes only with enough trials."""
    if value is None:
        return None
    return False if value > 0 else (True if enough else None)


def within(value, limit, enough, strict=False):
    if value is None or not enough:
        return None
    if value == NEVER:
        return False
    return value < limit if strict else value <= limit


def evaluate(cells, rows):
    summaries = {cell["id"]: summarize(rows, cell) for cell in cells}
    checks = []
    for cell in cells:
        summary = summaries[cell["id"]]
        needed = MANUAL_TRIALS if cell["manual"] else MINIMUM_TRIALS
        enough = summary["trials"] >= needed
        tag = {"cell": cell["id"]}
        checks.append({**check("trials", enough or None, f"{summary['trials']} of {needed}"), **tag})
        checks.append({**check("crashes", zero_count(summary["crashes"], enough), summary["crashes"]), **tag})
        checks.append({**check("doubleDelivery", zero_count(summary["doubleDeliveries"], enough),
                               summary["doubleDeliveries"]), **tag})
        checks.append({**check("deliveredAfterCancel", zero_count(summary["deliveredAfterCancel"], enough),
                               summary["deliveredAfterCancel"]), **tag})
        if cell["dictating"] == "secreteo":
            checks.append({**check("lostAudio", zero_count(summary["lostFrames"], enough), summary["lostFrames"]),
                           **tag})
            checks.append({**check("delivery", zero_count(summary["missingDeliveries"], enough),
                                   f"{summary['missingDeliveries']} stops typed nothing"), **tag})
        else:
            # Portavoz reports no frame counts; a stop that typed nothing is the only outside sign of loss.
            checks.append({**check("lostAudio", zero_count(summary["missingDeliveries"], enough),
                                   f"indirect: {summary['missingDeliveries']} stops typed nothing"), **tag,
                           "indirect": True})
        if cell["event"] == "sleep":
            continue
        p95 = summary["timeToFirstTextP95"]
        checks.append({**check("timeToFirstTextCeiling", within(p95, FIRST_TEXT_CEILING, enough), p95), **tag})
        control = cell["control"] and summaries[cell["control"]]
        if not control:
            continue
        pair = {**tag, "control": cell["control"]}
        control_p95 = control["timeToFirstTextP95"]
        if NEVER in (p95, control_p95):
            ratio = None if control_p95 == NEVER else NEVER
        else:
            ratio = None if p95 is None or not control_p95 else p95 / control_p95
        checks.append({**check("timeToFirstTextRatio", within(ratio, FIRST_TEXT_RATIO_LIMIT, enough), ratio), **pair})
        if cell["ending"] == "stop":
            caption, control_caption = summary["captionLatencyP95"], control["captionLatencyP95"]
            if NEVER in (caption, control_caption):
                rise = None if control_caption == NEVER else NEVER
            else:
                rise = None if caption is None or control_caption is None else caption - control_caption
            checks.append({**check("captionLatencyRise", within(rise, CAPTION_RISE_LIMIT, enough, strict=True), rise),
                           **pair})
    results = {item["result"] for item in checks}
    verdict = "fail" if "fail" in results else "incomplete" if "missing" in results else "pass"
    return {"verdict": verdict, "cells": summaries, "checks": checks}


def resources_summary(rows):
    pressure = [row["resources"]["memoryFreePercent"] for row in rows
                if row.get("resources", {}).get("memoryFreePercent") is not None]
    swap = [row["resources"]["swapUsedBytes"] for row in rows if row.get("resources", {}).get("swapUsedBytes") is not None]
    return {"lowestMemoryFreePercent": min(pressure, default=None), "highestSwapUsedBytes": max(swap, default=None)}


def write_report(output, cells, rows, run):
    result = evaluate(cells, rows)
    report = {"schemaVersion": 1, "kind": "spike-two-apps-report", "dryRun": run.get("dryRun", False),
              "thresholds": {"captionRiseSeconds": CAPTION_RISE_LIMIT, "firstTextRatio": FIRST_TEXT_RATIO_LIMIT,
                             "firstTextCeilingSeconds": FIRST_TEXT_CEILING, "minimumTrials": MINIMUM_TRIALS,
                             "manualTrials": MANUAL_TRIALS},
              "environment": run.get("environment", {}), **result, "resources": resources_summary(rows)}
    write_json(output / "report.json", report)
    lines = [f"# Spike 1 result{' (dry run, not evidence)' if report['dryRun'] else ''}", "",
             f"Verdict: **{result['verdict']}**", "",
             "| Cell | Trials | First text p95 | Caption p95 | Lost frames | Double | Crashes |",
             "|---|---|---|---|---|---|---|"]

    def fmt(value):
        return "–" if value is None else f"{value:.3f}" if isinstance(value, float) else str(value)

    for cell in cells:
        summary = result["cells"][cell["id"]]
        lines.append(f"| {cell['id']} | {summary['trials']} | {fmt(summary['timeToFirstTextP95'])} | "
                     f"{fmt(summary['captionLatencyP95'])} | {fmt(summary['lostFrames'])} | "
                     f"{summary['doubleDeliveries']} | {summary['crashes']} |")
    failing = [item for item in result["checks"] if item["result"] != "pass"]
    if failing:
        lines += ["", "## Not passing", ""]
        lines += [f"- {item['cell']}: {item['check']} {item['result']} ({item['detail']})" for item in failing]
    (output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report


# MARK: Bundle

def write_json(path, document):
    temporary = path.with_name("." + path.name + ".tmp")
    temporary.write_text(json.dumps(document, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def read_rows(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def prepare_output(output):
    output = Path(output)
    require(output.is_absolute(), "--output must be an absolute path")
    resolved = output.resolve()
    require(resolved != ROOT and ROOT not in resolved.parents, "results stay outside the repository")
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    return output


# MARK: Drivers

class SimulatedDriver:
    """A deterministic stand-in for two apps, so the whole pipeline runs without either one."""

    def __init__(self, seed=1):
        self.random = random.Random(seed)
        self.clock = 1_800_000_000.0
        self.prompts = []

    def identity(self):
        return {"simulated": True}

    def preflight(self, cells):
        return {"simulated": True}

    def prepare_group(self, dictating):
        self.prompts.append(f"take dictation in {dictating}")

    def setup_block(self, cell, launch_order):
        self.clock += 20

    def teardown_block(self, cell):
        self.clock += 2
        return []

    def prompt(self, message):
        self.prompts.append(message)

    def trial(self, cell, case):
        self.clock += 5
        trigger = self.clock
        load = 1.2 if cell["modelState"] == "cold" else 0.0
        load *= 1.15 if cell["model"] == "parakeetUltra" else 1.0
        busy = 0.08 if cell["companion"] else 0.0
        busy += 0.1 if cell["background"] == "meeting" else 0.0
        first = trigger + 0.45 + load + busy + self.random.uniform(0, 0.15)
        start = trigger + LEAD_SECONDS
        speech_end = start + case["speechSeconds"]
        panel = [{"t": trigger + 0.05, "words": 0, "revision": 0, "panel": True, "delivered": False},
                 {"t": first, "words": 1, "revision": 1, "panel": True, "delivered": False}]
        apps = [app for app in APPS if app == cell["dictating"] or cell["companion"]]
        observation = {"triggerAt": trigger, "playbackStartedAt": start, "settled": True,
                       "alive": dict.fromkeys(apps, True), "aliveAtStart": dict.fromkeys(apps, True)}
        if cell["ending"] == "cancel":
            observation["cancelAt"] = min(first, trigger + CANCEL_CAP) + CANCEL_AFTER_TEXT
            insertions = []
        else:
            words = case["expectedWords"]
            settle = speech_end + 0.25 + busy + self.random.uniform(0, 0.1)
            panel.append({"t": settle, "words": words, "revision": 2, "panel": True, "delivered": False})
            observation["stopAt"] = settle + SETTLE_QUIET
            insertions = [{"t": observation["stopAt"] + 0.4, "characters": words * 5, "words": words}]
        observation["panel"] = panel
        observation["insertions"] = insertions
        if cell["dictating"] == "secreteo":
            outcome = "cancelled" if cell["ending"] == "cancel" else "dispatchReported"
            observation["timing"] = [{"startedAt": trigger + 0.01, "engine": cell["model"], "audio": {
                "paddingFrames": 0, "rejectedFrames": 0, "relayDroppedFrames": 0},
                "session": {"elapsedSeconds": {"firstCaptionHandled": first - trigger - 0.02}, "outcome": outcome}}]
        observation["resources"] = {"footprint": {app: 40_000_000 + self.random.randint(0, 5_000_000) for app in apps},
                                    "memoryFreePercent": 60, "swapUsedBytes": 0}
        self.clock = (observation.get("stopAt") or speech_end) + QUIET_WINDOW
        return observation


class RealDriver:
    """Drives the installed apps in the dedicated account. Needs Accessibility for the terminal."""

    def __init__(self, arguments, output):
        self.arguments = arguments
        self.output = output
        self.agent = output / "spike-agent"
        self.receiver_app = output / "SpikeReceiver.app"
        self.apps = {"secreteo": self.identity_of(arguments.secreteo_app),
                     "portavoz": self.identity_of(arguments.portavoz_app)}
        self.timing_log = output / "secreteo-timing.jsonl"
        self.receiver_log = output / "receiver.jsonl"
        self.receiver_pid = None
        self.uid = str(os.getuid())
        self.seen_crashes = set()
        self.started = time.time()

    @staticmethod
    def identity_of(path):
        path = Path(path).expanduser()
        info_path = path / "Contents/Info.plist"
        require(info_path.is_file(), f"no app at {path}")
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        return {"path": str(path), "bundleID": info["CFBundleIdentifier"], "executable": info["CFBundleExecutable"],
                "version": info.get("CFBundleShortVersionString", "?"), "build": info.get("CFBundleVersion", "?")}

    def identity(self):
        """What a resumed run must share with the rows already written."""
        return {"apps": {app: {key: value for key, value in identity.items() if key != "path"}
                         for app, identity in self.apps.items()},
                "device": self.arguments.device, "otherInput": self.arguments.other_input,
                "hotkeys": [self.arguments.secreteo_hotkey, self.arguments.portavoz_hotkey]}

    def run(self, command, timeout=60, check=True):
        result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False, text=True)
        if check and result.returncode != 0:
            raise SpikeError(f"{Path(command[0]).name} failed: {result.stderr.strip()[:200]}")
        return result.stdout

    def agent_json(self, *arguments, timeout=60):
        return json.loads(self.run([str(self.agent), *arguments], timeout=timeout).splitlines()[-1])

    def preflight(self, cells):
        require(sys.platform == "darwin", "the spike runs on macOS")
        require(shutil.which("swiftc"), "swiftc is missing: install the Xcode command line tools")
        self.run(["swiftc", "-O", "-swift-version", "5", str(AGENT_SOURCE), "-o", str(self.agent)], timeout=600)
        problems = []
        status = self.agent_json("check")
        if not status["accessibilityTrusted"]:
            problems.append("grant Accessibility to this terminal in System Settings > Privacy & Security")
        devices = {device["name"]: device for device in status["devices"]}
        loop = devices.get(self.arguments.device)
        if not loop or loop["inputChannels"] < 1 or loop["outputChannels"] < 1:
            problems.append(f"the loopback device {self.arguments.device!r} is not installed")
        other = devices.get(self.arguments.other_input)
        if not other or other["inputChannels"] < 1:
            problems.append(f"the other input {self.arguments.other_input!r} is missing")
        if self.apps["secreteo"]["bundleID"] == SHIPPED_SECRETEO:
            problems.append("use the Dev identity from make install: the shipped app writes no timing log")
        if any(cell["background"] == "meeting" for cell in cells):
            shortcuts = set(self.run(["shortcuts", "list"]).splitlines())
            for name in (self.arguments.start_meeting, self.arguments.stop_meeting):
                if name not in shortcuts:
                    problems.append(f"create the Shortcut {name!r} (see the spike doc)")
        require(not problems, "preflight failed:\n- " + "\n- ".join(problems))
        self.loop_uid = loop["uid"]
        self.other_uid = other["uid"]
        portavoz = self.apps["portavoz"]["bundleID"]
        self.run(["defaults", "write", portavoz, "SUEnableAutomaticChecks", "-bool", "NO"])
        self.run(["defaults", "write", portavoz, "SUAutomaticallyUpdate", "-bool", "NO"])
        self.start_receiver()
        return {**self.identity(), **environment()}

    def start_receiver(self):
        # Inside a bundle, `open -a` can always bring it forward; a bare process may be refused.
        contents = self.receiver_app / "Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copy2(self.agent, contents / "MacOS/SpikeReceiver")
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleExecutable": "SpikeReceiver", "CFBundleIdentifier": "local.spike.receiver",
                           "CFBundleName": "Spike Receiver", "CFBundlePackageType": "APPL"}, stream)
        ready = Path(str(self.receiver_log) + ".ready")
        ready.unlink(missing_ok=True)
        self.run(["open", "-n", "-a", str(self.receiver_app), "--args", "receiver", "--out", str(self.receiver_log)])
        deadline = time.time() + 15
        while not ready.exists():
            require(time.time() < deadline, "the receiver window did not start")
            time.sleep(0.1)
        self.receiver_pid = json.loads(ready.read_text())["pid"]

    def front_receiver(self):
        os.kill(self.receiver_pid, signal.SIGUSR1)
        self.run(["open", "-a", str(self.receiver_app)])
        deadline = time.time() + 3
        while self.agent_json("front")["pid"] != self.receiver_pid:
            require(time.time() < deadline, "the receiver window would not come to the front")
            time.sleep(0.1)
        time.sleep(0.2)

    def pid(self, app):
        result = self.run(["pgrep", "-x", "-U", self.uid, self.apps[app]["executable"]], check=False)
        pids = [int(value) for value in result.split()]
        return pids[0] if pids else None

    def owner(self):
        try:
            return json.loads(OWNERSHIP_FILE.expanduser().read_text()).get("owner")
        except (OSError, ValueError):
            return None

    def wait_gone(self, app, seconds):
        deadline = time.time() + seconds
        while self.pid(app) is not None and time.time() < deadline:
            time.sleep(0.2)
        return self.pid(app) is None

    def quit(self, app):
        if self.pid(app) is None:
            return
        self.run(["osascript", "-e", f'tell application id "{self.apps[app]["bundleID"]}" to quit'], check=False)
        if self.wait_gone(app, 15):
            return
        for kill in (signal.SIGTERM, signal.SIGKILL):
            pid = self.pid(app)
            if pid is not None:
                os.kill(pid, kill)
            if self.wait_gone(app, 10):
                return
        raise SpikeError(f"{app} would not quit")

    def launch(self, app):
        extra = ["--args", "-dictation-timing-log", str(self.timing_log)] if app == "secreteo" else []
        self.run(["open", "-g", "-a", self.apps[app]["path"], *extra])
        deadline = time.time() + 30
        while self.pid(app) is None:
            require(time.time() < deadline, f"{app} did not start")
            time.sleep(0.2)
        time.sleep(3)

    def prepare_group(self, dictating):
        for app in APPS:
            if self.pid(app) is None:
                self.launch(app)
        wanted = self.apps[dictating]["bundleID"]
        while self.owner() != wanted:
            self.prompt(f"Take dictation in {dictating} from its menu (or Settings), then press Return.")

    def configure(self, cell):
        for app in APPS:
            identity = self.apps[app]["bundleID"]
            # Both apps read these keys; anything that adds a step or a second session stays off.
            for key, kind, value in (("dictationAutoStop", "-bool", "NO"), ("dictationCompactIndicator", "-bool", "NO"),
                                     ("dictationCorrectionCommands", "-bool", "NO"),
                                     ("dictationTextMode", "-string", "clean")):
                self.run(["defaults", "write", identity, key, kind, value])
            self.run(["defaults", "delete", identity, "dictationTranslationTarget"], check=False)
        dictating = self.apps[cell["dictating"]]["bundleID"]
        self.run(["defaults", "write", dictating, "dictationLiveSpeechEngine", cell["model"]])
        self.run(["defaults", "write", dictating, "preferredInputUID", self.loop_uid])
        if cell["background"] == "meeting":
            uid = self.loop_uid if cell["microphone"] == "same" else self.other_uid
            self.run(["defaults", "write", self.apps["portavoz"]["bundleID"], "preferredInputUID", uid])

    def setup_block(self, cell, launch_order):
        for app in APPS:
            self.quit(app)
        self.configure(cell)
        for app in launch_order:
            if app == cell["dictating"] or cell["companion"]:
                self.launch(app)
        require(self.owner() == self.apps[cell["dictating"]]["bundleID"], "ownership moved during the run")
        if cell["background"] == "meeting":
            self.run(["shortcuts", "run", self.arguments.start_meeting], timeout=60)
            time.sleep(3)

    def teardown_block(self, cell):
        if cell["background"] == "meeting":
            self.run(["shortcuts", "run", self.arguments.stop_meeting], timeout=120, check=False)
        # Crash reports land seconds after the crash; the block's last trial may have missed one.
        time.sleep(5)
        return self.crashes()

    def prompt(self, message):
        print("\a" + message, file=sys.stderr, flush=True)
        input()

    def read_lines(self, path, since):
        if not path.exists():
            return []
        rows = []
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("t", row.get("startedAt", since)) >= since - 1:
                rows.append(row)
        return rows

    def trial(self, cell, case):
        dictating = cell["dictating"]
        apps = [app for app in APPS if app == dictating or cell["companion"]]
        observation = {"aliveAtStart": {app: self.pid(app) is not None for app in apps}}
        stuck = self.pid(dictating) and self.agent_json("watch", "--once", "--pid", str(self.pid(dictating)))["panel"]
        if cell["modelState"] == "cold" or stuck or not observation["aliveAtStart"][dictating]:
            # A panel left open (recovery, a notice) would swallow the next trigger.
            self.quit(dictating)
            self.launch(dictating)
        self.front_receiver()
        watch_log = self.output / "panel.tmp.jsonl"
        watch_log.unlink(missing_ok=True)
        watcher = subprocess.Popen([str(self.agent), "watch", "--pid", str(self.pid(dictating)),
                                    "--out", str(watch_log)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        hotkey = self.arguments.secreteo_hotkey if dictating == "secreteo" else self.arguments.portavoz_hotkey
        player = None
        try:
            observation["triggerAt"] = self.agent_json(
                "key", "--combo", hotkey, "--require-front", str(self.receiver_pid))["postedAt"]
            time.sleep(LEAD_SECONDS)
            player = subprocess.Popen([str(self.agent), "play", "--device", self.arguments.device, "--file", case["path"]],
                                      stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True)
            if cell["event"] == "sleep":
                self.prompt("Put the Mac to sleep now (Apple menu > Sleep), wake it after 10 s, then press Return.")
            elif cell["ending"] == "cancel":
                self.wait_for_text(watch_log, observation["triggerAt"] + CANCEL_CAP)
                time.sleep(CANCEL_AFTER_TEXT)
                observation["cancelAt"] = self.agent_json("key", "--combo", "esc")["postedAt"]
            output, _ = player.communicate(timeout=case["seconds"] + 600)
            lines = output.splitlines()
            # Sleep can take the audio device away mid-file; the trial still counts.
            require(lines or cell["event"] == "sleep", "playback failed")
            observation["playbackStartedAt"] = (json.loads(lines[-1])["startedAt"] if lines
                                                else observation["triggerAt"] + LEAD_SECONDS)
            if cell["ending"] == "stop" and cell["event"] != "sleep":
                speech_end = observation["playbackStartedAt"] + case["speechSeconds"]
                observation["settled"] = self.wait_for_settle(watch_log, speech_end)
                observation["stopAt"] = self.agent_json("key", "--combo", hotkey)["postedAt"]
                self.wait_for_delivery(observation["triggerAt"])
            time.sleep(QUIET_WINDOW)
            trigger = observation["triggerAt"]
            observation["panel"] = self.read_lines(watch_log, trigger)
        finally:
            watcher.terminate()
            watcher.wait(timeout=10)
            if player is not None and player.poll() is None:
                player.kill()
            watch_log.unlink(missing_ok=True)
        observation["insertions"] = [row for row in self.read_lines(self.receiver_log, trigger) if row["t"] >= trigger]
        observation["timing"] = self.read_lines(self.timing_log, trigger)
        observation["crashes"] = self.crashes()
        observation["alive"] = {app: self.pid(app) is not None for app in apps}
        observation["resources"] = self.resources(apps)
        return observation

    def wait_for_text(self, path, deadline):
        while time.time() < deadline and not any(sample["words"] > 0 for sample in self.read_lines(path, 0)):
            time.sleep(0.05)

    def wait_for_settle(self, path, speech_end):
        last_change, previous = time.time(), None
        deadline = speech_end + SETTLE_CAP
        while time.time() < deadline:
            samples = self.read_lines(path, 0)
            revision = samples[-1].get("revision", 0) if samples else 0
            if revision != previous:
                last_change, previous = (samples[-1]["t"] if samples else time.time()), revision
            if time.time() >= speech_end and time.time() - last_change >= SETTLE_QUIET:
                return True
            time.sleep(0.1)
        return False

    def wait_for_delivery(self, trigger):
        deadline = time.time() + DELIVERY_CAP
        while time.time() < deadline:
            if any(row["t"] >= trigger for row in self.read_lines(self.receiver_log, trigger)):
                return
            time.sleep(0.1)

    def crashes(self):
        """New crash reports for either app since the run began, each counted once."""
        folder = Path("~/Library/Logs/DiagnosticReports").expanduser()
        names = [identity["executable"] for identity in self.apps.values()]
        found = []
        for path in sorted(folder.glob("*.ips")) if folder.is_dir() else []:
            if (path.name not in self.seen_crashes and path.stat().st_mtime >= self.started
                    and any(path.name.startswith(name) for name in names)):
                self.seen_crashes.add(path.name)
                found.append(path.name)
        return found

    def resources(self, apps):
        footprint = {}
        for app in apps:
            pid = self.pid(app)
            if pid is None:
                continue
            match = re.search(r"Footprint: ([\d.]+) (KB|MB|GB)", self.run(["footprint", "-p", str(pid)], check=False))
            if match:
                footprint[app] = int(float(match[1]) * {"KB": 1 << 10, "MB": 1 << 20, "GB": 1 << 30}[match[2]])
        pressure = re.search(r"free percentage: (\d+)%", self.run(["memory_pressure", "-Q"], check=False))
        swap = re.search(r"used = ([\d.]+)M", self.run(["sysctl", "-n", "vm.swapusage"], check=False))
        return {"footprint": footprint, "memoryFreePercent": int(pressure[1]) if pressure else None,
                "swapUsedBytes": int(float(swap[1]) * (1 << 20)) if swap else None}

    def close(self):
        if self.receiver_pid:
            try:
                os.kill(self.receiver_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def environment():
    def read(command):
        try:
            return subprocess.run(command, capture_output=True, text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return None
    return {"chip": read(["sysctl", "-n", "machdep.cpu.brand_string"]), "memoryBytes": read(["sysctl", "-n", "hw.memsize"]),
            "macOS": read(["sw_vers", "-buildVersion"]), "power": (read(["pmset", "-g", "batt"]) or "").split("\n")[0]}


# MARK: Run

def execute(output, cells, blocks, cases, driver, *, manual=True, dry_run=False, log=print):
    rows_path = output / "rows.jsonl"
    # Simulated rows and rows from another build must never merge into one result.
    plan = {"cells": cells, "blocks": blocks, "cases": [case["caseID"] for case in cases],
            "dryRun": dry_run, "identity": driver.identity()}
    plan_path = output / "plan.json"
    if plan_path.exists():
        require(json.loads(plan_path.read_text())["fingerprint"] == fingerprint(plan),
                "this folder holds another plan, build or a dry run; use a new --output")
    else:
        write_json(plan_path, {"fingerprint": fingerprint(plan), **plan})
    done = {(row["cell"], row["trial"]) for row in read_rows(rows_path)
            if not row.get("warmup") and not row.get("error") and not row.get("lateCrash")}
    run = {"dryRun": dry_run, "environment": driver.preflight(cells), "startedAt": time.time()}
    write_json(output / "run.json", run)
    by_id = {cell["id"]: cell for cell in cells}
    group = None
    failures = 0
    with rows_path.open("a", encoding="utf-8") as stream:
        os.chmod(rows_path, 0o600)

        def write(row):
            stream.write(json.dumps(row, sort_keys=True) + "\n")
            stream.flush()

        for block in blocks:
            cell = by_id[block["cell"]]
            pending = [trial for trial in block["trials"] if (cell["id"], trial) not in done]
            if not pending or (cell["manual"] and not manual):
                continue
            if group != cell["dictating"]:
                group = cell["dictating"]
                driver.prepare_group(group)
            if cell["event"] == "bluetooth":
                driver.prompt("Connect the Bluetooth headset now and leave the apps' input on the loopback; press Return.")
            driver.setup_block(cell, block["launchOrder"])
            plan_trials = ([None] if cell["modelState"] == "warm" else []) + pending
            for trial in plan_trials:
                case = cases[(trial or 0) % len(cases)]
                row = {"cell": cell["id"], "trial": trial, "caseID": case["caseID"], "warmup": trial is None,
                       "launchOrder": block["launchOrder"]}
                try:
                    observation = driver.trial(cell, case)
                    row.update(measure(observation, cell, case))
                    row["triggerAt"] = observation["triggerAt"]
                    problem = trial_problem(row, cell)
                    if problem:
                        row["error"] = problem
                except KeyboardInterrupt:
                    raise
                except Exception as error:  # noqa: BLE001 - a trial's failure is recorded, never fatal by itself
                    row["error"] = f"{type(error).__name__}: {error}"[:300]
                failures = failures + 1 if row.get("error") else 0
                write(row)
                require(failures < 3, f"three trials in a row failed ({row.get('error')}); "
                                      "fix the cause and run the same command to resume")
            late = driver.teardown_block(cell)
            if late:
                write({"cell": cell["id"], "trial": None, "warmup": False, "lateCrash": True, "crashes": late})
            if cell["event"] == "bluetooth":
                driver.prompt("Disconnect the Bluetooth headset; press Return.")
            log(f"{cell['id']}: trials {block['trials'][0]}-{block['trials'][-1]} done")
    return write_report(output, cells, read_rows(rows_path), run)


def parse(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("plan", help="print the cells, the schedule size and an estimate")
    run = commands.add_parser("run", help="run every pending trial and write the report")
    report = commands.add_parser("report", help="score the rows already in --output")
    for command in (plan, run):
        command.add_argument("--trials", type=int, default=MINIMUM_TRIALS)
        command.add_argument("--manual-trials", type=int, default=MANUAL_TRIALS)
        command.add_argument("--block", type=int, default=10)
    for command in (run, report):
        command.add_argument("--output", required=True, help="new absolute folder outside the repository")
    run.add_argument("--corpus", type=Path, help="folder from materialize_dictation_corpus.py")
    run.add_argument("--dry-run", action="store_true", help="simulated apps; checks the pipeline, measures nothing")
    run.add_argument("--automated-only", action="store_true", help="skip the Bluetooth and sleep cells")
    run.add_argument("--secreteo-app", default="/Applications/Secreteo Dev.app")
    run.add_argument("--portavoz-app", default="~/Applications/Portavoz.app")
    run.add_argument("--device", default="BlackHole 2ch")
    run.add_argument("--other-input", default="MacBook Pro Microphone")
    run.add_argument("--secreteo-hotkey", default="ctrl+opt+cmd+d")
    run.add_argument("--portavoz-hotkey", default="opt+cmd+d")
    run.add_argument("--start-meeting", default="Spike Start Meeting")
    run.add_argument("--stop-meeting", default="Spike Stop Meeting")
    return parser.parse_args(argv)


def main(argv=None):
    arguments = parse(argv)
    try:
        if arguments.command == "report":
            output = prepare_output(arguments.output)
            plan = json.loads((output / "plan.json").read_text())
            run = json.loads((output / "run.json").read_text())
            report = write_report(output, plan["cells"], read_rows(output / "rows.jsonl"), run)
            print(json.dumps({"verdict": report["verdict"]}))
            return 0 if report["verdict"] == "pass" else 1
        dry_run = getattr(arguments, "dry_run", False)
        require(arguments.trials >= MINIMUM_TRIALS or dry_run, f"every automated cell needs {MINIMUM_TRIALS} trials")
        require(arguments.manual_trials >= MANUAL_TRIALS or dry_run,
                f"the owner decided on {MANUAL_TRIALS} trials for each manual cell")
        require(arguments.trials >= 1 and arguments.manual_trials >= 1, "every cell needs a trial")
        cells = build_cells(arguments.trials, arguments.manual_trials)
        blocks = schedule(cells, arguments.block)
        if arguments.command == "plan":
            automated = [cell for cell in cells if not cell["manual"]]
            print(json.dumps({"automatedCells": len(automated), "manualCells": len(cells) - len(automated),
                              "trials": sum(cell["trials"] for cell in cells), "blocks": len(blocks),
                              "estimatedHours": round(estimate_seconds(cells, blocks) / 3600, 1),
                              "cells": [cell["id"] for cell in cells]}, indent=2))
            return 0
        require(dry_run or arguments.corpus, "--corpus is required unless --dry-run")
        output = prepare_output(arguments.output)
        cases = corpus_cases(arguments.corpus.resolve() if arguments.corpus else None)
        driver = SimulatedDriver() if dry_run else RealDriver(arguments, output)
        try:
            report = execute(output, cells, blocks, cases, driver, manual=not arguments.automated_only,
                             dry_run=dry_run, log=lambda message: print(message, file=sys.stderr, flush=True))
        finally:
            if isinstance(driver, RealDriver):
                driver.close()
        print(json.dumps({"verdict": report["verdict"], "report": str(output / "report.md")}))
        return 0 if report["verdict"] == "pass" else 1
    except (SpikeError, corpus.CorpusError, OSError) as error:
        print("spike: " + str(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("spike: stopped; run the same command again to resume", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
