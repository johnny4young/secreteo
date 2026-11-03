import importlib.util
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ci_changes = load("ci_changes")
ci_gate = load("ci_gate")


def needs(code="true", delivery="true", **results):
    jobs = {"hygiene": "success", "lint": "success", "changes": "success", "unit": "success"}
    jobs.update(results)
    payload = {name: {"result": result} for name, result in jobs.items()}
    payload["changes"]["outputs"] = {"code": code, "delivery": delivery}
    return payload


class ChangesTests(unittest.TestCase):
    def test_docs_only_is_not_code(self):
        self.assertFalse(ci_changes.classify(["docs/A.md", "README.md", "site/index.html"])["code"])

    def test_any_source_file_is_code(self):
        self.assertTrue(ci_changes.classify(["docs/A.md", "Sources/AppUI/A.swift"])["code"])

    def test_workflow_change_is_code(self):
        self.assertTrue(ci_changes.classify([".github/workflows/ci.yml"])["code"])

    def test_an_empty_diff_never_skips(self):
        self.assertEqual(ci_changes.classify([]), {"code": True, "delivery": True})

    def test_delivery_and_triggers_select_the_signed_lane(self):
        self.assertTrue(ci_changes.classify(["Sources/Delivery/TextInserter.swift"])["delivery"])
        self.assertTrue(ci_changes.classify(["Sources/Triggers/GlobalHotkey.swift"])["delivery"])
        self.assertFalse(ci_changes.classify(["Sources/AppUI/A.swift"])["delivery"])


class GateTests(unittest.TestCase):
    def test_all_green_passes(self):
        self.assertEqual(ci_gate.failures(needs()), [])

    def test_a_failure_fails(self):
        self.assertTrue(ci_gate.failures(needs(unit="failure")))

    def test_a_cancelled_job_fails(self):
        self.assertTrue(ci_gate.failures(needs(unit="cancelled")))

    def test_skipping_unit_on_a_code_change_fails(self):
        self.assertTrue(ci_gate.failures(needs(code="true", unit="skipped")))

    def test_skipping_unit_on_docs_passes(self):
        self.assertEqual(ci_gate.failures(needs(code="false", unit="skipped")), [])

    def test_a_failure_on_docs_still_fails(self):
        self.assertTrue(ci_gate.failures(needs(code="false", unit="failure")))

    def test_a_missing_scope_cannot_skip(self):
        payload = needs(unit="skipped")
        payload["changes"]["outputs"] = {}
        self.assertTrue(ci_gate.failures(payload))

    def test_hygiene_can_never_be_skipped(self):
        self.assertTrue(ci_gate.failures(needs(code="false", hygiene="skipped")))

    def test_a_failed_scope_job_fails(self):
        self.assertTrue(ci_gate.failures(needs(changes="failure")))

    def test_the_signed_lane_follows_its_own_scope(self):
        self.assertEqual(ci_gate.failures(needs(delivery="false", **{"signed-handoff": "skipped"})), [])
        self.assertTrue(ci_gate.failures(needs(delivery="true", **{"signed-handoff": "skipped"})))

    def test_the_author_is_not_an_input(self):
        payload = needs(unit="skipped")
        payload["actor"] = {"result": "dependabot[bot]"}
        self.assertTrue(ci_gate.failures(payload))


if __name__ == "__main__":
    unittest.main()
