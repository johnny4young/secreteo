#!/usr/bin/env bash
# Lints inside SwiftLint's own image, pinned by digest, so the runner's libraries never matter.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="ghcr.io/realm/swiftlint:0.65.0@sha256:a482729f4b58741875af1566f23397f3f6db300372756fc31606d0a4527fab9e"

docker run --rm --network none --mount "type=bind,source=$ROOT,target=/work,readonly" --workdir /work "$image" \
  lint --strict --no-cache --reporter github-actions-logging
