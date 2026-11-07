import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# Stdout is the MCP protocol channel there, not a log.
STDOUT_ALLOWED = {"Sources/DictationAgents/DictationMCPCommand.swift"}
UNREDACTED = re.compile(r"(?:privacy:\s*|OSLogPrivacy\s*=\s*)(?:OSLogPrivacy)?\.public\b")
RAW_OUTPUT = re.compile(
    r"(?<![\w.])(?:(?:Swift|Foundation|Darwin)\.)?(print|debugPrint|NSLog|os_log|dump|fputs|fwrite|puts)\("
    r"|FileHandle\.standard(?:Error|Output)|STD(?:ERR|OUT)_FILENO")
CRASH_CALL = re.compile(r"(?<![\w.])(fatalError|preconditionFailure|precondition|assertionFailure|assert)\(")
# The message argument's position in each crash call.
MESSAGE_INDEX = {"fatalError": 0, "preconditionFailure": 0, "assertionFailure": 0, "precondition": 1, "assert": 1}
PLAIN_LITERAL = re.compile(r'"[^"\\]*"')
COMMENT = re.compile(r"^\s*(?://|/\*|\*)")


def swift_files():
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "Sources", "Apps"],
        cwd=REPO, check=True, capture_output=True, text=True).stdout.split()
    for name in sorted(listed):
        if name.endswith(".swift") and (REPO / name).is_file():
            yield name, without_comments((REPO / name).read_text())


def without_comments(text):
    # Blanks comment lines but keeps the line count, so offsets map to line numbers.
    return "\n".join("" if COMMENT.match(line) else line for line in text.split("\n"))


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def call_arguments(text, start):
    """Top-level arguments of the call whose opening parenthesis is at `start`."""
    depth, quoted, args, current = 0, False, [], []
    for index in range(start, len(text)):
        char = text[index]
        if quoted:
            current.append(char)
            if char == "\\" and index + 1 < len(text):
                continue
            if char == '"' and text[index - 1] != "\\":
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char in "([{":
            depth += 1
            if depth == 1:
                continue
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                args.append("".join(current).strip())
                return [arg for arg in args if arg]
        elif char == "," and depth == 1:
            args.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    return args


def unsafe_crash_messages(text):
    for match in CRASH_CALL.finditer(text):
        args = call_arguments(text, match.end() - 1)
        index = MESSAGE_INDEX[match.group(1)]
        if len(args) > index and not PLAIN_LITERAL.fullmatch(args[index]):
            yield match.start()


class LogPrivacyTests(unittest.TestCase):
    """Unified logging redacts interpolated values unless marked public, so no value is."""

    def test_no_log_marks_a_value_public(self):
        offenders = [
            f"{name}:{line_of(text, match.start())}"
            for name, text in swift_files() for match in UNREDACTED.finditer(text)
        ]
        self.assertEqual(offenders, [], "a public log value can carry dictated text")

    def test_crash_messages_are_plain_literals(self):
        offenders = [
            f"{name}:{line_of(text, offset)}"
            for name, text in swift_files() for offset in unsafe_crash_messages(text)
        ]
        self.assertEqual(offenders, [], "a crash report keeps its message unredacted")

    def test_only_the_mcp_command_writes_to_stdout(self):
        offenders = [
            f"{name}:{line_of(text, match.start())}"
            for name, text in swift_files() for match in RAW_OUTPUT.finditer(text)
            if not (name in STDOUT_ALLOWED and match.group(1) == "print")
        ]
        self.assertEqual(offenders, [], "print and NSLog skip redaction")

    def test_the_patterns_catch_what_they_guard(self):
        for public in ('"\\(text, privacy: .public)"', "\\(text, privacy:\n    .public)",
                       "\\(text, privacy: OSLogPrivacy.public)", "let p: OSLogPrivacy = .public"):
            self.assertTrue(UNREDACTED.search(public), public)
        self.assertIsNone(UNREDACTED.search("\\(text, privacy: .publicDetail)"))
        for raw in ("print(text)", "debugPrint(x)", "NSLog(format)", "os_log(format)", "dump(record)",
                    "fputs(text, stderr)", "fwrite(buffer, 1, n, stdout)", "puts(text)", "Swift.print(text)",
                    "Foundation.NSLog(format)", "FileHandle.standardError.write(data)",
                    "FileHandle.standardOutput.write(data)", "write(STDERR_FILENO, buffer, n)"):
            self.assertTrue(RAW_OUTPUT.search(raw), raw)
        for safe in ("controller.print(document)", "fingerprint(part)", "outputs(x)"):
            self.assertIsNone(RAW_OUTPUT.search(safe), safe)
        for unsafe in ('fatalError("bad \\(text)")', 'fatalError(\n    "bad \\(text)")', "fatalError(error.localizedDescription)",
                       'preconditionFailure("\\(x)")', 'assertionFailure(message)', 'precondition(ok,\n    "bad \\(text)")',
                       "assert(ok, String(describing: error))"):
            self.assertTrue(list(unsafe_crash_messages(unsafe)), unsafe)
        for safe in ('fatalError("unreachable")', "fatalError()", "precondition(count > 0)",
                     'assert(items.contains(where: { $0 > 1 }), "empty")', 'precondition(a, "it\'s, fine")'):
            self.assertEqual(list(unsafe_crash_messages(safe)), [], safe)
        self.assertEqual(without_comments("/// privacy: .public\nlet x = 1"), "\nlet x = 1")


if __name__ == "__main__":
    unittest.main()
