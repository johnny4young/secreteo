import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# Hand-built dependencies default to the app's real stop tail; the fixture's skip it.
MEMBERWISE = re.compile(r"\bDictationSessionDependencies(?:\.init)?\(")
LIVE = re.compile(r"(?:\bDictationSessionDependencies)?\.live\(services:")


def swift_files():
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "Tests"],
        cwd=REPO, check=True, capture_output=True, text=True).stdout.split()
    for name in sorted(listed):
        if name.endswith(".swift") and (REPO / name).is_file():
            yield name, (REPO / name).read_text()


def call_end(text, opening):
    """Index just past the parenthesis that closes the one at `opening`."""
    depth = 0
    for index in range(opening, len(text)):
        depth += {"(": 1, ")": -1}.get(text[index], 0)
        if depth == 0:
            return index + 1
    return len(text)


def offenders(files):
    found = []
    for name, text in files:
        for match in MEMBERWISE.finditer(text):
            arguments = text[match.end() - 1:call_end(text, match.end() - 1)]
            if not re.search(r"\bwaitForStopTail:", arguments):
                found.append(f"{name}:{text.count(chr(10), 0, match.start()) + 1}")
        for match in LIVE.finditer(text):
            # Reading one member of the live value is fine; keeping it would dictate with the real tail.
            if not text.startswith(".", call_end(text, text.index("(", match.start()))):
                found.append(f"{name}:{text.count(chr(10), 0, match.start()) + 1}")
    return found


class StopTailInTestsTests(unittest.TestCase):
    def test_hand_built_dependencies_choose_their_stop_tail(self):
        self.assertEqual(offenders(swift_files()), [], "pass waitForStopTail, or build through the fixture")

    def test_the_check_catches_what_it_guards(self):
        caught = {
            "DictationSessionDependencies(a: { f(x) }, b: 1)": True,
            "DictationSessionDependencies.init(a: 1)": True,
            "DictationSessionDependencies(a: 1, waitForStopTail: t, b: 2)": False,
            "DictationSessionDependencies(a: 1)\nother.waitForStopTail = t": True,
            "let d: DictationSessionDependencies = .live(services: s, beginCapture: { {} })": True,
            "toggle(using: DictationSessionDependencies.live(services: s, beginCapture: { {} }))": True,
            "DictationSessionDependencies.live(services: s, beginCapture: { {} }).waitForStopTail": False,
            "feature.makeDictationSessionDependencies()": False,
        }
        for text, expected in caught.items():
            self.assertEqual(bool(offenders([("a.swift", text)])), expected, text)


if __name__ == "__main__":
    unittest.main()
