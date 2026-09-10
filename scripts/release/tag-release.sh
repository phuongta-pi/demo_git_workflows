#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Tag Release (gate)
#
# Đóng tag vX.Y.Z trên nhánh release. Hai điều kiện:
#   1. audit-pick 0 UNKNOWN
#   2. nhánh release local == origin (đã push, QC test đúng bản này)
#
# Script KHÔNG push tag. Xem lại rồi: git push origin vX.Y.Z
#
# Usage:   bash scripts/release/tag-release.sh <release/vX.Y.Z|vX.Y.Z> [message]
#
# Biến môi trường:
#   NO_FETCH=1  không fetch / không so với origin (test offline)
# ==============================================================================

set -euo pipefail

TARGET="${1:-}"
MESSAGE="${2:-}"
[[ -n "$TARGET" ]] || { echo "Usage: $0 <release/vX.Y.Z|vX.Y.Z> [message]" >&2; exit 2; }

TAG_NAME="${TARGET#release/}"
[[ "$TAG_NAME" =~ ^v ]] || TAG_NAME="v$TAG_NAME"
RELEASE_BRANCH="release/$TAG_NAME"
[[ -n "$MESSAGE" ]] || MESSAGE="Release $TAG_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "${NO_FETCH:-}" == "1" ]] || git fetch --quiet --tags origin 2>/dev/null || true

git rev-parse --verify --quiet "$RELEASE_BRANCH^{commit}" >/dev/null || { echo "Error: '$RELEASE_BRANCH' không có local." >&2; exit 1; }
if git rev-parse --verify --quiet "refs/tags/$TAG_NAME" >/dev/null; then
  echo "Error: tag '$TAG_NAME' đã tồn tại." >&2
  exit 1
fi

if [[ "${NO_FETCH:-}" != "1" ]] && git rev-parse --verify --quiet "origin/$RELEASE_BRANCH" >/dev/null; then
  if [[ "$(git rev-parse "$RELEASE_BRANCH")" != "$(git rev-parse "origin/$RELEASE_BRANCH")" ]]; then
    echo "Error: $RELEASE_BRANCH local khác origin. Push (hoặc pull) trước — tag phải đúng bản QC đã test." >&2
    exit 1
  fi
fi

echo "==> Gate: audit pick $RELEASE_BRANCH"
if ! bash "$SCRIPT_DIR/audit-pick.sh" "$RELEASE_BRANCH"; then
  echo "" >&2
  echo "GATE BLOCKED: còn PR UNKNOWN — pick lên release hoặc hold-pr.sh rồi chạy lại." >&2
  exit 1
fi

git tag -a "$TAG_NAME" -m "$MESSAGE" "$RELEASE_BRANCH"
echo ""
echo "Đã tạo tag $TAG_NAME tại $(git rev-parse --short "$TAG_NAME") ($RELEASE_BRANCH)."
echo "Tiếp theo:"
echo "  git push origin $TAG_NAME"
echo "  Leader chạy workflow 'Deploy Firebase picareprod' với ref = $TAG_NAME"
