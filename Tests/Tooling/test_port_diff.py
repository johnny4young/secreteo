import importlib.util
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
spec = importlib.util.spec_from_file_location("port_diff", SCRIPTS / "port_diff.py")
port_diff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(port_diff)


class PortDiffTests(unittest.TestCase):
    def run_diff(self, change: str, ported: str, source: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "repo"
            export = Path(folder) / "export"
            (root / "docs").mkdir(parents=True)
            export.mkdir()
            (root / "a.swift").write_text(ported)
            (export / "b.swift").write_text(source)
            (root / "docs/PROVENANCE.md").write_text(
                f"## Dictation code\n\n| `a.swift` | `b.swift` | {change} |\n\n## Other\n\n| `x` | `y` | z |\n")
            output = StringIO()
            with redirect_stdout(output):
                code = port_diff.main([str(export)], root)
            return code, output.getvalue()

    def test_a_rename_alone_matches(self):
        code, output = self.run_diff("Renames", "import DictationKit\nlet a = 1\n", "import PortavozCore\nlet a = 1\n")

        self.assertEqual(code, 0)
        self.assertIn("a.swift: same", output)

    def test_any_other_change_to_a_renamed_file_fails(self):
        code, output = self.run_diff("Renames", "let a = 2\n", "let a = 1\n")

        self.assertEqual(code, 1)
        self.assertIn("DIFFERS", output)
        self.assertIn("+let a = 2", output)

    def test_a_seam_prints_its_differences_without_failing(self):
        code, output = self.run_diff("Seam: drops b", "let a = 1\n", "let a = 1\nlet b = 2\n")

        self.assertEqual(code, 0)
        self.assertIn("-let b = 2", output)

    def test_an_extract_shows_only_what_it_added(self):
        code, output = self.run_diff("Extract: one test", "import Testing\nlet a = 1\n", "let a = 1\nlet b = 2\n")

        self.assertEqual(code, 0)
        self.assertIn("+import Testing", output)
        self.assertNotIn("let b = 2", output)

    def test_rows_outside_the_section_are_ignored(self):
        _, output = self.run_diff("Renames", "let a = 1\n", "let a = 1\n")

        self.assertNotIn("x:", output)


if __name__ == "__main__":
    unittest.main()
