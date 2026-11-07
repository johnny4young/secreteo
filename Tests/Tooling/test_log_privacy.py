import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# Stdout is the MCP protocol channel there, not a log.
STDOUT_ALLOWED = {"Sources/DictationAgents/DictationMCPCommand.swift"}
UNREDACTED = re.compile(r"privacy:\s*\.public")
RAW_OUTPUT = re.compile(r"(?<![\w.])(?:print|debugPrint|NSLog|os_log|dump|fputs)\(|FileHandle\.standardError")
# A crash message lands in the crash report unredacted.
INTERPOLATED_CRASH = re.compile(
    r"(?<![\w.])(?:fatalError|preconditionFailure|precondition|assertionFailure|assert)\([^\n]*\\\(")


def swift_files():
    for root in ("Sources", "Apps"):
        yield from sorted((REPO / root).rglob("*.swift"))


def code_lines():
    for path in swift_files():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if not line.lstrip().startswith("//"):
                yield str(path.relative_to(REPO)), number, line


class LogPrivacyTests(unittest.TestCase):
    """Unified logging redacts interpolated values unless marked public, so no value is."""

    def test_no_log_marks_a_value_public(self):
        # Whole files, so a marker wrapped onto the next line still counts.
        offenders = [str(path.relative_to(REPO)) for path in swift_files() if UNREDACTED.search(path.read_text())]
        self.assertEqual(offenders, [], "a public log value can carry dictated text")

    def test_no_crash_message_interpolates_a_value(self):
        offenders = [f"{path}:{number}" for path, number, line in code_lines() if INTERPOLATED_CRASH.search(line)]
        self.assertEqual(offenders, [], "a crash report keeps its message unredacted")

    def test_only_the_mcp_command_writes_to_stdout(self):
        offenders = [
            f"{path}:{number}" for path, number, line in code_lines()
            if RAW_OUTPUT.search(line) and path not in STDOUT_ALLOWED
        ]
        self.assertEqual(offenders, [], "print and NSLog skip redaction")

    def test_the_patterns_catch_what_they_guard(self):
        self.assertTrue(UNREDACTED.search('log("\\(text, privacy: .public)")'))
        self.assertTrue(RAW_OUTPUT.search("    print(text)"))
        self.assertTrue(RAW_OUTPUT.search("NSLog(format)"))
        self.assertIsNone(RAW_OUTPUT.search("controller.print(document)"))
        self.assertIsNone(RAW_OUTPUT.search("fingerprint(part)"))
        self.assertTrue(RAW_OUTPUT.search("FileHandle.standardError.write(data)"))
        self.assertTrue(UNREDACTED.search("\\(text, privacy:\n    .public)"))
        self.assertTrue(INTERPOLATED_CRASH.search('fatalError("bad \\(text)")'))
        self.assertIsNone(INTERPOLATED_CRASH.search('fatalError("unreachable")'))


if __name__ == "__main__":
    unittest.main()
