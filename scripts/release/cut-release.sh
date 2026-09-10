#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Cut Release Branch
# Rule:
#   - Lần 1 cắt từ `dev`
#   - Lần 2+ cắt từ `tag prod` (latest production release tag)
# Usage: bash scripts/release/cut-release.sh <version>
# Example: bash scripts/release/cut-release.sh v1.2.0
# ==============================================================================

set -eo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Error: Version argument missing."
  echo "Usage: $0 <vX.Y.Z>"
  echo "Example: $0 v1.2.0"
  exit 1
fi

# Ensure version format
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  VERSION="v$VERSION"
fi

RELEASE_BRANCH="release/$VERSION"

# Check if branch already exists
if git rev-parse --verify "$RELEASE_BRANCH" >/dev/null 2>&1; then
  echo "Error: Branch '$RELEASE_BRANCH' already exists."
  exit 1
fi

# Check for latest production tag
LATEST_TAG=$(git tag -l "v*" --sort=-v:refname | head -n 1)

BASE_REF=""
CUT_REASON=""

if [[ -z "$LATEST_TAG" ]]; then
  # Lần 1: Cắt từ dev
  DEV_REF="dev"
  if ! git rev-parse --verify "$DEV_REF" >/dev/null 2>&1; then
    DEV_REF=$(git rev-parse --verify main >/dev/null 2>&1 && echo "main" || echo "HEAD")
  fi
  BASE_REF="$DEV_REF"
  CUT_REASON="Lần 1: Cắt từ nhánh '$DEV_REF' (chưa có tag prod nào trước đó)"
else
  # Lần 2+: Cắt từ tag prod
  BASE_REF="$LATEST_TAG"
  CUT_REASON="Lần 2+: Cắt từ latest tag prod '$LATEST_TAG'"
fi

echo "==> Creating branch '$RELEASE_BRANCH' from $BASE_REF..."
echo "==> Lý do: $CUT_REASON"

git checkout -b "$RELEASE_BRANCH" "$BASE_REF"

echo "✅ Created and switched to branch '$RELEASE_BRANCH'."
echo "Bước tiếp theo:"
echo "  1. Chạy audit pick: bash scripts/release/audit-pick.sh $RELEASE_BRANCH --md"
echo "  2. Cherry-pick các PR mong muốn vào release: bash scripts/release/pick-to-release.sh $RELEASE_BRANCH <PR...>"
echo "  3. Push release branch lên origin để CI auto deploy Firebase Staging (picarestg)"
