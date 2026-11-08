import importlib.util
import re
import subprocess
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ci_changes = load("ci_changes")
ci_gate = load("ci_gate")
ci_reuse_gate = load("ci_reuse_gate")

REPO = "owner/repo"
MERGED = "m" * 40
HEAD = "h" * 40


def needs(code="true", delivery="true", release="true", **results):
    jobs = {"hygiene": "success", "lint": "success", "changes": "success", "unit": "success", "ui-smoke": "success",
            "signed-handoff": "success", "release-dryrun": "success"}
    jobs.update(results)
    payload = {name: {"result": result} for name, result in jobs.items()}
    payload["changes"]["outputs"] = {"code": code, "delivery": delivery, "release": release}
    return payload


class ChangesTests(unittest.TestCase):
    def test_docs_only_is_not_code(self):
        self.assertFalse(ci_changes.classify(["docs/A.md", "README.md", "site/index.html"])["code"])

    def test_any_source_file_is_code(self):
        self.assertTrue(ci_changes.classify(["docs/A.md", "Sources/AppUI/A.swift"])["code"])

    def test_workflow_change_is_code(self):
        self.assertTrue(ci_changes.classify([".github/workflows/ci.yml"])["code"])

    def test_an_empty_diff_never_skips(self):
        self.assertEqual(ci_changes.classify([]), {"code": True, "delivery": True, "release": True})

    def test_delivery_and_triggers_select_the_signed_lane(self):
        self.assertTrue(ci_changes.classify(["Sources/DictationSession/Delivery/TextInserter.swift"])["delivery"])
        self.assertTrue(ci_changes.classify(["Tests/DictationSessionTests/Delivery/TextInsertionTargetTests.swift"])["delivery"])
        self.assertFalse(ci_changes.classify(["Sources/DictationSession/DictationController.swift"])["delivery"])
        self.assertTrue(ci_changes.classify(["Sources/DictationSession/Triggers/GlobalHotkey.swift"])["delivery"])
        self.assertTrue(ci_changes.classify(["Tests/DictationSessionTests/Triggers/HotkeySettingTests.swift"])["delivery"])
        self.assertFalse(ci_changes.classify(["Sources/AppUI/A.swift"])["delivery"])

    def test_ci_machinery_runs_every_lane(self):
        for path in (".github/workflows/ci.yml", "scripts/ci_changes.py", "scripts/ci_gate.py", "scripts/ci_reuse_gate.py"):
            self.assertEqual(ci_changes.classify([path]), {"code": True, "delivery": True, "release": True}, path)

    def test_packaging_selects_the_release_dry_run(self):
        for path in ("scripts/package-release.sh", "project.yml", "Apps/Secreteo/SparkleUpdater.swift"):
            self.assertTrue(ci_changes.classify([path])["release"], path)
        self.assertFalse(ci_changes.classify(["Sources/AppUI/A.swift"])["release"])
        self.assertFalse(ci_changes.classify(["Apps/Secreteo/Localizable.xcstrings"])["release"])


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

    def test_release_dry_run_may_skip_only_when_scoped_out(self):
        self.assertEqual(ci_gate.failures(needs(release="false", **{"release-dryrun": "skipped"})), [])
        self.assertTrue(ci_gate.failures(needs(release="true", **{"release-dryrun": "skipped"})))
        self.assertTrue(ci_gate.failures(needs(release="false", **{"release-dryrun": "failure"})))

    def test_a_job_missing_from_needs_fails_in_every_scope(self):
        for job in ("ui-smoke", "unit", "signed-handoff", "release-dryrun"):
            for flag in ("true", "false"):
                payload = needs(code=flag, delivery=flag, release=flag)
                del payload[job]
                self.assertTrue(ci_gate.failures(payload), (job, flag))

    def test_the_author_is_not_an_input(self):
        payload = needs(unit="skipped")
        payload["actor"] = {"result": "dependabot[bot]"}
        self.assertTrue(ci_gate.failures(payload))


def github(merged_tree="t1", head_tree="t1", pulls=None, runs=None, gates=None):
    """A fake `gh api` for a squash merge of HEAD into MERGED."""
    if pulls is None:
        pulls = [{"merge_commit_sha": MERGED, "merged_at": "2026-11-05T00:00:00Z", "head": {"sha": HEAD}}]
    if runs is None:
        runs = [{"id": 7, "path": ".github/workflows/ci.yml", "html_url": "https://example.test/runs/7"}]
    if gates is None:
        gates = {7: "success"}
    responses = {
        f"repos/{REPO}/commits/{MERGED}/pulls": pulls,
        f"repos/{REPO}/git/commits/{MERGED}": {"tree": {"sha": merged_tree}},
        f"repos/{REPO}/git/commits/{HEAD}": {"tree": {"sha": head_tree}},
        f"repos/{REPO}/actions/runs?head_sha={HEAD}&event=pull_request&per_page=100": {"workflow_runs": runs},
    }
    for run, conclusion in gates.items():
        jobs = [{"name": "unit", "conclusion": "success"}, {"name": "gate", "conclusion": conclusion}]
        responses[f"repos/{REPO}/actions/runs/{run}/jobs"] = {"jobs": jobs}
    return responses.__getitem__


class ReuseGateTests(unittest.TestCase):
    def proof(self, **world):
        return ci_reuse_gate.proof(github(**world), REPO, MERGED)

    def test_the_tree_a_pull_request_proved_reuses_its_gate(self):
        self.assertEqual(self.proof(), "https://example.test/runs/7")

    def test_a_different_tree_runs_everything(self):
        self.assertIsNone(self.proof(head_tree="t2"))

    def test_a_failed_gate_runs_everything(self):
        self.assertIsNone(self.proof(gates={7: "failure"}))

    def test_an_unfinished_gate_runs_everything(self):
        self.assertIsNone(self.proof(gates={7: None}))

    def test_only_the_newest_run_counts(self):
        runs = [{"id": 7, "path": ".github/workflows/ci.yml", "html_url": "old"},
                {"id": 9, "path": ".github/workflows/ci.yml", "html_url": "new"}]
        self.assertIsNone(self.proof(runs=runs, gates={7: "success", 9: "failure"}))
        self.assertEqual(self.proof(runs=runs, gates={7: "failure", 9: "success"}), "new")

    def test_a_gate_job_from_another_workflow_does_not_count(self):
        runs = [{"id": 7, "path": ".github/workflows/other.yml", "html_url": "other"}]
        self.assertIsNone(self.proof(runs=runs))

    def test_a_commit_no_pull_request_merged_runs_everything(self):
        self.assertIsNone(self.proof(pulls=[]))
        open_pull = {"merge_commit_sha": MERGED, "merged_at": None, "head": {"sha": HEAD}}
        self.assertIsNone(self.proof(pulls=[open_pull]))
        other = {"merge_commit_sha": "x" * 40, "merged_at": "2026-11-05T00:00:00Z", "head": {"sha": HEAD}}
        self.assertIsNone(self.proof(pulls=[other]))

    def test_any_api_error_runs_everything(self):
        failure = subprocess.CalledProcessError(1, ["gh", "api"])
        for error in (failure, KeyError("tree"), ValueError("not JSON")):
            with mock.patch.object(ci_reuse_gate, "gh_api", side_effect=error), \
                    mock.patch("sys.argv", ["ci_reuse_gate.py", REPO, MERGED]), \
                    mock.patch("sys.stderr"):
                self.assertEqual(ci_reuse_gate.main(), 1, error)

    def test_a_proven_tree_exits_zero(self):
        with mock.patch.object(ci_reuse_gate, "gh_api", side_effect=github()), \
                mock.patch("sys.argv", ["ci_reuse_gate.py", REPO, MERGED]), \
                mock.patch("sys.stdout"):
            self.assertEqual(ci_reuse_gate.main(), 0)


class BuildCacheTests(unittest.TestCase):
    """The unit job restores what build-cache.yml saves only if both agree on key and flags."""

    WORKFLOWS = SCRIPTS.parent / ".github" / "workflows"

    def job(self, workflow: str, name: str) -> str:
        text = (self.WORKFLOWS / workflow).read_text()
        start = text.index(f"\n  {name}:\n")
        end = text.find("\n\n  ", start + 1)
        return text[start:end if end != -1 else len(text)]

    def test_the_unit_job_restores_the_saved_key(self):
        saved = re.search(r"key: (.+?)\$\{\{ github\.run_id \}\}", self.job("build-cache.yml", "swift-build"))
        unit = self.job("ci.yml", "unit")
        self.assertIsNotNone(saved)
        self.assertIn(f"key: {saved.group(1)}\n", unit)
        self.assertIn(f"            {saved.group(1)}\n", unit, "the resolved-hash prefix must be a restore key")
        self.assertIn("actions/cache/restore@", unit)
        self.assertNotIn("actions/cache/save@", unit, "pull requests must not evict main's cache")

    def test_both_jobs_build_with_the_same_flags(self):
        flags = lambda job: sorted(set(re.findall(r"run: swift (?:build|test)\b.*?((?:-Xswiftc \S+ ?)+)$", job, re.M)))
        unit, cache = self.job("ci.yml", "unit"), self.job("build-cache.yml", "swift-build")
        self.assertEqual(flags(unit), flags(cache))
        self.assertIn("swift build --build-tests", cache, "tests must be in the cache too")


if __name__ == "__main__":
    unittest.main()
