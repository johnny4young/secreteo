#!/usr/bin/env python3
"""Exits 0 only when a push to main lands the exact tree a merged pull request proved through `gate`.

Usage: ci_reuse_gate.py <owner/repo> <sha>. Any doubt or error exits 1, and CI runs everything.
"""
import json
import subprocess
import sys

WORKFLOW = ".github/workflows/ci.yml"


def gh_api(path: str):
    result = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def proof(api, repo: str, sha: str) -> str | None:
    """The URL of the pull request run whose `gate` covers this commit, or None."""
    pulls = [pull for pull in api(f"repos/{repo}/commits/{sha}/pulls")
             if pull.get("merge_commit_sha") == sha and pull.get("merged_at")]
    if len(pulls) != 1:
        return None
    head = pulls[0]["head"]["sha"]
    if api(f"repos/{repo}/git/commits/{sha}")["tree"]["sha"] != api(f"repos/{repo}/git/commits/{head}")["tree"]["sha"]:
        return None
    runs = api(f"repos/{repo}/actions/runs?head_sha={head}&event=pull_request&per_page=100")["workflow_runs"]
    runs = [run for run in runs if run.get("path") == WORKFLOW]
    if not runs:
        return None
    # A rerun keeps its id, and the jobs endpoint answers for its latest attempt.
    newest = max(runs, key=lambda run: run["id"])
    gates = [job for job in api(f"repos/{repo}/actions/runs/{newest['id']}/jobs")["jobs"] if job.get("name") == "gate"]
    if len(gates) != 1 or gates[0].get("conclusion") != "success":
        return None
    return newest["html_url"]


def main() -> int:
    repo, sha = sys.argv[1:3]
    try:
        url = proof(gh_api, repo, sha)
    except Exception as error:  # A failed proof only costs a full run.
        print(f"Could not prove reuse, running every job: {error}", file=sys.stderr)
        return 1
    if url is None:
        print("No merged pull request proved this tree, running every job.")
        return 1
    print(f"This tree passed gate in {url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
