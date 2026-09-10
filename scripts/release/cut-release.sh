#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Cut Release Branch
#
# Rule:
#   - Lần 1 (chưa có tag prod)  -> cắt từ dev
#   - Lần 2+                    -> cắt từ tag prod mới nhất
#   - Chỉ cắt đợt mới khi đợt trước đã lên prod (mọi release/* trên origin đều đã có tag).
#     Bỏ qua kiểm tra này bằng --force.
#
# Usage:   bash scripts/release/cut-release.sh <vX.Y.Z> [--force]
# Example: bash scripts/release/cut-release.sh v1.2.0
#
# Biến môi trường:
#   NO_FETCH=1  không fetch origin (test offline)
# ==============================================================================

set -euo pipefail

VERSION="${1:-}"
FORCE="${2:-}"
[[ -n "$VERSION" ]] || { echo "Usage: $0 <vX.Y.Z> [--force]" >&2; exit 2; }
[[ "$VERSION" =~ ^v ]] || VERSION="v$VERSION"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] || { echo "Error: version phải dạng vX.Y.Z." >&2; exit 2; }
RELEASE_BRANCH="release/$VERSION"

[[ "${NO_FETCH:-}" == "1" ]] || git fetch --quiet --tags origin 2>/dev/null || true

if git rev-parse --verify --quiet "$RELEASE_BRANCH" >/dev/null || git rev-parse --verify --quiet "origin/$RELEASE_BRANCH" >/dev/null; then
  echo "Error: '$RELEASE_BRANCH' đã tồn tại." >&2
  exit 1
fi

# Đợt trước chưa lên prod? (release/* trên origin mà version chưa có tag)
if [[ "$FORCE" != "--force" ]]; then
  while IFS= read -r br; do
    [[ -n "$br" ]] || continue
    v="${br#origin/release/}"
    if ! git rev-parse --verify --quiet "refs/tags/$v" >/dev/null; then
      echo "Error: $br chưa có tag $v (đợt trước chưa lên prod). Tag/đóng đợt đó trước, hoặc --force." >&2
      exit 1
    fi
  done < <(git branch -r --list 'origin/release/*' --format='%(refname:short)')
fi

LATEST_TAG="$(git tag -l 'v*' --sort=-v:refname | head -n 1)"
if [[ -z "$LATEST_TAG" ]]; then
  BASE_REF="$(git rev-parse --verify --quiet origin/dev >/dev/null && echo origin/dev || echo dev)"
  REASON="lần 1: chưa có tag prod, cắt từ $BASE_REF"
else
  BASE_REF="$LATEST_TAG"
  REASON="lần 2+: cắt từ tag prod mới nhất $LATEST_TAG"
fi

git checkout --quiet -b "$RELEASE_BRANCH" "$BASE_REF"
echo "Đã tạo $RELEASE_BRANCH từ $BASE_REF ($REASON)."
echo "Tiếp theo:"
echo "  git push -u origin $RELEASE_BRANCH            # CI auto deploy staging"
echo "  bash scripts/release/audit-pick.sh $RELEASE_BRANCH"
echo "  bash scripts/release/pick-to-release.sh $RELEASE_BRANCH <pr...>"
