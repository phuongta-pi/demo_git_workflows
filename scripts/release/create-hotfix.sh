#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Create Hotfix Branch
# Rule: Hotfix branch is ALWAYS created from production tag (tag prod)
# Usage: bash scripts/release/create-hotfix.sh <hotfix-name> [base-tag]
# Example: bash scripts/release/create-hotfix.sh fix-login v1.2.0
# ==============================================================================

set -eo pipefail

HOTFIX_NAME="${1:-}"
BASE_TAG="${2:-}"

if [[ -z "$HOTFIX_NAME" ]]; then
  echo "Error: Hotfix name missing."
  echo "Usage: $0 <hotfix-name> [base-tag]"
  echo "Example: $0 fix-login v1.2.0"
  exit 1
fi

HOTFIX_BRANCH="hotfix/$HOTFIX_NAME"

if [[ -z "$BASE_TAG" ]]; then
  # Auto-detect latest production tag
  BASE_TAG=$(git tag -l "v*" --sort=-v:refname | head -n 1)
  if [[ -z "$BASE_TAG" ]]; then
    echo "Error: No production tag found. Please specify base-tag manually."
    exit 1
  fi
fi

echo "==> Creating hotfix branch '$HOTFIX_BRANCH' from tag '$BASE_TAG'..."
git checkout -b "$HOTFIX_BRANCH" "$BASE_TAG"

echo "✅ Created and switched to hotfix branch '$HOTFIX_BRANCH'."
echo "Quy trình hotfix sau khi code và test xong:"
echo "  1. Tạo PR từ '$HOTFIX_BRANCH' vào nhánh release hiện tại (để CI deploy Staging picarestg & QC kiểm thử)"
echo "  2. Tạo PR (back-port) từ '$HOTFIX_BRANCH' vào nhánh 'dev' (để không bị mất fix trong các đợt phát triển tiếp theo)"
