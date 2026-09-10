#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Hold PR
#
# Gắn nhãn hold:vX.Y.Z lên PR (tạo nhãn nếu chưa có). PR có nhãn này = "không ra đợt
# vX.Y.Z", audit-pick xếp vào HOLD. Sang đợt sau nhãn không còn khớp -> tự về UNKNOWN.
#
# Usage:   bash scripts/release/hold-pr.sh <vX.Y.Z|release/vX.Y.Z> <pr>...
# Example: bash scripts/release/hold-pr.sh v1.2.0 3925 3931
# ==============================================================================

set -euo pipefail

VERSION="${1:-}"
shift || true
if [[ -z "$VERSION" || $# -eq 0 ]]; then
  echo "Usage: $0 <vX.Y.Z> <pr>..." >&2
  exit 2
fi
VERSION="${VERSION#release/}"
[[ "$VERSION" =~ ^v ]] || VERSION="v$VERSION"
LABEL="hold:$VERSION"

command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI required." >&2; exit 2; }

if ! gh label list --limit 500 --json name --jq '.[].name' | grep -qx "$LABEL"; then
  gh label create "$LABEL" --color D97706 --description "Không ra đợt $VERSION (audit-pick: HOLD)"
fi

for pr in "$@"; do
  pr="${pr#\#}"
  gh pr edit "$pr" --add-label "$LABEL" >/dev/null
  echo "hold  #$pr  ← $LABEL"
done
