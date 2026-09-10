#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Create Hotfix Branch
#
# Rule: hotfix/* LUÔN tạo từ tag prod đang chạy (mặc định: tag v* mới nhất).
# Sau khi fix: PR vào release/vX.Y.Z (QC test staging) + PR vào dev (back-port).
#
# Usage:   bash scripts/release/create-hotfix.sh <name> [base-tag]
# Example: bash scripts/release/create-hotfix.sh fix-login v1.2.0
#
# Biến môi trường:
#   NO_FETCH=1  không fetch tags (test offline)
# ==============================================================================

set -euo pipefail

NAME="${1:-}"
BASE_TAG="${2:-}"
[[ -n "$NAME" ]] || { echo "Usage: $0 <name> [base-tag]" >&2; exit 2; }
HOTFIX_BRANCH="hotfix/$NAME"

[[ "${NO_FETCH:-}" == "1" ]] || git fetch --quiet --tags origin 2>/dev/null || true

if [[ -z "$BASE_TAG" ]]; then
  BASE_TAG="$(git tag -l 'v*' --sort=-v:refname | head -n 1)"
  [[ -n "$BASE_TAG" ]] || { echo "Error: chưa có tag prod nào — truyền base-tag." >&2; exit 1; }
fi
git rev-parse --verify --quiet "refs/tags/$BASE_TAG" >/dev/null || { echo "Error: tag '$BASE_TAG' không tồn tại." >&2; exit 1; }

git checkout --quiet -b "$HOTFIX_BRANCH" "$BASE_TAG"
echo "Đã tạo $HOTFIX_BRANCH từ tag $BASE_TAG."
echo "Sau khi fix xong:"
echo "  1. PR $HOTFIX_BRANCH → release/$BASE_TAG   (CI deploy staging, QC test, rồi tag patch)"
echo "  2. PR $HOTFIX_BRANCH → dev                 (back-port, mở cùng lúc)"
