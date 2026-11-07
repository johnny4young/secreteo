import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import ui_test_shards  # noqa: E402


class UITestShardTests(unittest.TestCase):
    def test_every_ui_test_class_runs_in_exactly_one_shard(self):
        found = ui_test_shards.test_classes()

        halves = ui_test_shards.shards(found, 2)

        self.assertEqual(sorted(name for half in halves for name in half), sorted(found))
        self.assertFalse(set(halves[0]) & set(halves[1]))

    def test_shards_stay_within_one_class_of_each_other(self):
        found = ui_test_shards.test_classes()

        sizes = [sum(found[name] for name in half) for half in ui_test_shards.shards(found, 2)]

        self.assertLessEqual(max(sizes) - min(sizes), max(found.values()))

    def test_a_base_class_without_tests_is_not_sharded(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            (root / "Support.swift").write_text("class BaseUITestCase: XCTestCase {}\n")
            (root / "MenuUITests.swift").write_text(
                "final class MenuUITests: BaseUITestCase {\n    func testOpens() {}\n    func testCloses() {}\n}\n")

            found = ui_test_shards.test_classes(root)

        self.assertEqual(found, {"MenuUITests": 2})

    def test_two_test_classes_in_one_file_are_refused(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            (root / "Both.swift").write_text(
                "final class AUITests: XCTestCase {\n    func testA() {}\n}\n"
                "final class BUITests: XCTestCase {\n    func testB() {}\n}\n")

            with self.assertRaises(SystemExit):
                ui_test_shards.test_classes(root)


if __name__ == "__main__":
    unittest.main()
