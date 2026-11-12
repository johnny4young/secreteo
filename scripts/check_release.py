#!/usr/bin/env python3
"""Decides whether a tag may become a release, and extracts its notes from the changelog.

Usage: check_release.py check <tag>
       check_release.py notes <version>
`check` reads GLOBAL_DICTATION_CLEARED (the one version the owner cleared) from the environment and expects `origin/main` to be fetched.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECTION = re.compile(r"^## v?(?P<version>[^\s]+).*$", re.MULTILINE)


def project_setting(project_yml: str, name: str) -> str:
    match = re.search(rf'^\s*{name}:\s*"?([^"\n]*)"?\s*$', project_yml, re.MULTILINE)
    return match.group(1) if match else ""


def parent_key(lines: list[str], index: int) -> str:
    indent = len(lines[index]) - len(lines[index].lstrip())
    for line in reversed(lines[:index]):
        if line.strip() and not line.lstrip().startswith("#") and len(line) - len(line.lstrip()) < indent:
            return line.strip()
    return ""


def release_notes(changelog: str, version: str) -> str:
    sections = list(SECTION.finditer(changelog))
    for index, section in enumerate(sections):
        if section.group("version") == version:
            end = sections[index + 1].start() if index + 1 < len(sections) else len(changelog)
            return changelog[section.end():end].strip()
    return ""


def arms_global_dictation(project_yml: str) -> bool:
    # The base value is what a Release build gets. Anything but an explicit NO counts as armed.
    lines = project_yml.splitlines()
    values = [
        match.group(1)
        for index, line in enumerate(lines)
        if (match := re.match(r'\s*SECRETEO_GLOBAL_DICTATION:\s*"?([^"\s#]*)', line))
        and parent_key(lines, index) != "Debug:"
    ]
    return not values or any(value != "NO" for value in values)


def problems(tag: str, project_yml: str, changelog: str, on_main: bool, arms_dictation: bool,
             cleared_version: str) -> list[str]:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        return [f"{tag} is not vX.Y.Z"]
    version = tag[1:]
    found = []
    marketing = project_setting(project_yml, "MARKETING_VERSION")
    if marketing != version:
        found.append(f"the tag says {version}, and MARKETING_VERSION says {marketing}")
    if not project_setting(project_yml, "SPARKLE_PUBLIC_ED_KEY"):
        found.append("SPARKLE_PUBLIC_ED_KEY is empty, so this build could never update")
    if not release_notes(changelog, version):
        found.append(f"CHANGELOG.md has no entries under ## {version}")
    if not on_main:
        found.append("the tagged commit is not on main")
    if arms_dictation and cleared_version != version:
        found.append(f"this build arms global dictation, and GLOBAL_DICTATION_CLEARED is not {version}")
    return found


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ("check", "notes"):
        sys.exit(__doc__)
    command, argument = sys.argv[1], sys.argv[2]
    changelog = (ROOT / "CHANGELOG.md").read_text()
    if command == "notes":
        notes = release_notes(changelog, argument)
        if not notes:
            sys.exit(f"CHANGELOG.md has no entries under ## {argument}")
        print(notes)
        return
    on_main = subprocess.run(["git", "merge-base", "--is-ancestor", "HEAD", "origin/main"], cwd=ROOT,
                             check=False).returncode == 0
    project_yml = (ROOT / "project.yml").read_text()
    found = problems(argument, project_yml, changelog, on_main,
                     arms_global_dictation(project_yml), os.environ.get("GLOBAL_DICTATION_CLEARED", "").strip())
    for problem in found:
        print(f"::error::{problem}")
    if found:
        sys.exit(1)
    print(f"{argument} may be released")


if __name__ == "__main__":
    main()
