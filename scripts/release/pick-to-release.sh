#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Pick to Release
# Usage: bash scripts/release/pick-to-release.sh <release-branch> <pr_number_or_sha>...
# Example: bash scripts/release/pick-to-release.sh release/v1.2.0 3931 3940
# ==============================================================================

set -eo pipefail

RELEASE_BRANCH="${1:-}"
shift || true

if [[ -z "$RELEASE_BRANCH" || $# -eq 0 ]]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <release-branch> <pr_number_or_sha>..."
  echo "Example: $0 release/v1.2.0 3931 3940"
  exit 1
fi

TARGET_ITEMS=("$@")

# Save current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Checkout release branch
echo "==> Switching to branch '$RELEASE_BRANCH'..."
git checkout "$RELEASE_BRANCH"

DEV_BRANCH="dev"
if ! git rev-parse --verify "$DEV_BRANCH" >/dev/null 2>&1; then
  if git rev-parse --verify "origin/dev" >/dev/null 2>&1; then
    DEV_BRANCH="origin/dev"
  else
    DEV_BRANCH=$(git rev-parse --verify main >/dev/null 2>&1 && echo "main" || echo "HEAD")
  fi
fi

for ITEM in "${TARGET_ITEMS[@]}"; do
  COMMIT_SHA=""

  # Check if item is already a git commit hash
  if git rev-parse --verify "$ITEM^{commit}" >/dev/null 2>&1; then
    COMMIT_SHA=$(git rev-parse "$ITEM")
  else
    # Treat as PR number
    PR_NUM=$(echo "$ITEM" | sed 's/^#//')
    echo "==> Resolving PR #$PR_NUM on $DEV_BRANCH..."

    # Try gh CLI first
    if command -v gh >/dev/null 2>&1; then
      MERGE_COMMIT=$(gh pr view "$PR_NUM" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || echo "")
      if [[ -n "$MERGE_COMMIT" && "$MERGE_COMMIT" != "null" ]]; then
        COMMIT_SHA="$MERGE_COMMIT"
      fi
    fi

    # Fallback to git log search
    if [[ -z "$COMMIT_SHA" ]]; then
      COMMIT_SHA=$(git log "$DEV_BRANCH" --grep="(#$PR_NUM)" -n 1 --format="%H" 2>/dev/null || echo "")
    fi
    if [[ -z "$COMMIT_SHA" ]]; then
      COMMIT_SHA=$(git log "$DEV_BRANCH" --grep="#$PR_NUM" -n 1 --format="%H" 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$COMMIT_SHA" ]]; then
    echo "❌ Error: Could not resolve commit for item '$ITEM' on branch $DEV_BRANCH."
    continue
  fi

  SUBJ=$(git log -1 --format="%s" "$COMMIT_SHA")
  echo "==> Cherry-picking with -x: $COMMIT_SHA ($SUBJ)..."

  # Execute git cherry-pick -x
  if git cherry-pick -x "$COMMIT_SHA"; then
    echo "✅ Successfully picked $COMMIT_SHA to $RELEASE_BRANCH"
  else
    echo "⚠️ Conflict occurred while cherry-picking $COMMIT_SHA."
    echo "Please resolve conflicts, run 'git cherry-pick --continue', or 'git cherry-pick --abort'."
    exit 1
  fi
done

echo ""
echo "🎉 All requested items have been picked to $RELEASE_BRANCH."
echo "You can verify with: bash scripts/release/audit-pick.sh $RELEASE_BRANCH --md"

# Return to initial branch if different
if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]]; then
  git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true
fi
