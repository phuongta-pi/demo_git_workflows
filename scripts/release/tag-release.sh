#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Tag Release Gate
# Rule: Audit pick gate MUST pass (0 UNKNOWN) before creating tag
# Usage: bash scripts/release/tag-release.sh <release-branch-or-version> [message]
# Example: bash scripts/release/tag-release.sh release/v1.2.0 "Release v1.2.0"
# ==============================================================================

set -eo pipefail

TARGET="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$TARGET" ]]; then
  echo "Error: Release branch or version missing."
  echo "Usage: $0 <release/vX.Y.Z|vX.Y.Z> [message]"
  echo "Example: $0 release/v1.2.0 'Release v1.2.0'"
  exit 1
fi

# Determine branch and tag name
if [[ "$TARGET" =~ ^release/ ]]; then
  RELEASE_BRANCH="$TARGET"
  TAG_NAME="${TARGET#release/}"
else
  TAG_NAME="$TARGET"
  if [[ ! "$TAG_NAME" =~ ^v ]]; then
    TAG_NAME="v$TAG_NAME"
  fi
  RELEASE_BRANCH="release/$TAG_NAME"
fi

if [[ -z "$MESSAGE" ]]; then
  MESSAGE="Release $TAG_NAME"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [Gate 1/2] Running Audit Pick on $RELEASE_BRANCH..."
if ! bash "$SCRIPT_DIR/audit-pick.sh" "$RELEASE_BRANCH" --md; then
  echo ""
  echo "❌ GATE BLOCKED: Audit pick còn PR UNKNOWN. Không được tag!"
  echo "Vui lòng giải quyết tất cả PR (pick lên release hoặc gắn nhãn hold:vX.Y.Z)."
  exit 1
fi

echo ""
echo "==> [Gate 2/2] Audit pick PASSED! Proceeding to tag $TAG_NAME..."

# Ensure we are on the release branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]]; then
  git checkout "$RELEASE_BRANCH"
fi

# Check if tag already exists
if git rev-parse --verify "refs/tags/$TAG_NAME" >/dev/null 2>&1; then
  echo "Error: Tag '$TAG_NAME' already exists."
  exit 1
fi

# Create annotated tag
git tag -a "$TAG_NAME" -m "$MESSAGE"

echo "🎉 Successfully created tag '$TAG_NAME' on branch '$RELEASE_BRANCH'."
echo "Bước tiếp theo:"
echo "  1. Push tag: git push origin $TAG_NAME"
echo "  2. Leader kích hoạt GitHub Actions Deploy Prod (picareprod) với ref tag '$TAG_NAME'"
