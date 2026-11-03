#!/usr/bin/env bash
# Usage: enable-gatekeeper.sh. Hosted runners only: their images may turn it off, and then
# every `spctl -a` accepts anything.
set -euo pipefail

[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] || { echo "error: hosted runners only" >&2; exit 1; }
sudo spctl --global-enable
status="$(spctl --status)"
echo "$status"
[[ "$status" == "assessments enabled" ]] || { echo "error: Gatekeeper is still off" >&2; exit 1; }
