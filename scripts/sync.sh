#!/usr/bin/env bash
# Commit everything, rebase on origin, push — same flow as the other synced repos.
#
#   ./scripts/sync.sh "describe change"
#   ./scripts/sync.sh            # auto-generated message
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MSG="${1:-update $(date '+%Y-%m-%d %H:%M')}"

cd "$ROOT"
git add -A
if git diff --cached --quiet; then
    echo "nothing to commit"
else
    git commit -m "$MSG"
fi
git pull --rebase
git push
git status -sb | head -1
