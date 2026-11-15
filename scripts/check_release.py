#!/usr/bin/env python3
"""Decides whether a tag may become a release, and extracts its notes from the changelog.

Usage: check_release.py check <tag>
       check_release.py notes <version>
`check` expects `origin/main` and the tags to be fetched.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECTION = re.compile(r"^## v?(?P<version>[^\s]+).*$", re.MULTILINE)


def project_setting(project_yml: str, name: str) -> str:
    match = re.search(rf'^\s*{name}:\s*"?([^"\n]*)"?\s*$', project_yml, re.MULTILINE)
    return match.group(1) if match else ""


def release_notes(changelog: str, version: str) -> str:
    sections = list(SECTION.finditer(changelog))
    for index, section in enumerate(sections):
        if section.group("version") == version:
            end = sections[index + 1].start() if index + 1 < len(sections) else len(changelog)
            return changelog[section.end():end].strip()
    return ""


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def problems(tag: str, project_yml: str, changelog: str, on_main: bool, tags: list[str]) -> list[str]:
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
    # Sparkle and the cask only move forward, so an older version would never reach anyone.
    released = [other[1:] for other in tags if re.fullmatch(r"v\d+\.\d+\.\d+", other) and other != tag]
    newest = max(released, key=version_key, default="")
    if newest and version_key(version) <= version_key(newest):
        found.append(f"{tag} is not newer than v{newest}")
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
    tags = subprocess.run(["git", "tag", "--list", "v*"], cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout.split()
    found = problems(argument, project_yml, changelog, on_main, tags)
    for problem in found:
        print(f"::error::{problem}")
    if found:
        sys.exit(1)
    print(f"{argument} may be released")


if __name__ == "__main__":
    main()
