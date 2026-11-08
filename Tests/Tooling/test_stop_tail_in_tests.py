import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# Hand-built dependencies default to the app's real 250 ms tail; the fixture's skip it.
HAND_BUILT = re.compile(r"\bDictationSessionDependencies(?:\(|\.live\()")
CHOOSES_TAIL = re.compile(r"\bwaitForStopTail\b")


def test_sources():
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "Tests"],
        cwd=REPO, check=True, capture_output=True, text=True).stdout.split()
    for name in sorted(listed):
        if name.endswith(".swift") and (REPO / name).is_file():
            yield name, (REPO / name).read_text()


def offenders(files):
    return [name for name, text in files if HAND_BUILT.search(text) and not CHOOSES_TAIL.search(text)]


class StopTailInTestsTests(unittest.TestCase):
    def test_hand_built_dependencies_choose_their_stop_tail(self):
        self.assertEqual(offenders(test_sources()), [], "use the fixture's immediateStopTail or set waitForStopTail")

    def test_the_check_catches_what_it_guards(self):
        self.assertEqual(offenders([("a.swift", "DictationSessionDependencies(authorizeMicrophone: { true })")]),
                         ["a.swift"])
        self.assertEqual(offenders([("b.swift", ".live(services: s)"), ("c.swift", "DictationSessionDependencies.live(")]),
                         ["c.swift"])
        self.assertEqual(offenders([("d.swift", "DictationSessionDependencies(x)\nd.waitForStopTail = t")]), [])
        self.assertEqual(offenders([("e.swift", "feature.makeDictationSessionDependencies()")]), [])


if __name__ == "__main__":
    unittest.main()
