#!/usr/bin/env python3
"""The single required check. A job may be skipped only when the validated scope says so.

Usage: ci_gate.py <needs-json>, where the JSON is `toJSON(needs)` from the workflow.
The author of a change never affects the result.
"""
import json
import sys

ALWAYS = ("hygiene", "lint", "changes")
WHEN_CODE = ("unit", "ui-smoke")
WHEN_DELIVERY = ("signed-handoff",)
WHEN_RELEASE = ("release-dryrun",)


def failures(needs: dict) -> list[str]:
    problems = []
    for job in ALWAYS:
        result = needs.get(job, {}).get("result")
        if result != "success":
            problems.append(f"{job}: {result}")

    scope = needs.get("changes", {}).get("outputs", {})
    for jobs, flag in ((WHEN_CODE, "code"), (WHEN_DELIVERY, "delivery"), (WHEN_RELEASE, "release")):
        # Anything but an explicit "false" means the job had to run.
        may_skip = scope.get(flag) == "false"
        for job in jobs:
            result = needs.get(job, {}).get("result")
            if result != "success" and not (result == "skipped" and may_skip):
                problems.append(f"{job}: {result}")
    return problems


def main() -> None:
    problems = failures(json.loads(sys.argv[1]))
    for problem in problems:
        print(f"::error::{problem}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
