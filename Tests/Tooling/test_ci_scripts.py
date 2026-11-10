import importlib.util
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


ci_reuse_gate = load("ci_reuse_gate")

REPO = "owner/repo"
MERGED = "m" * 40
HEAD = "h" * 40


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


if __name__ == "__main__":
    unittest.main()
