#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Pick to Release
#
# Cherry-pick (-x) các PR đã merge vào dev lên nhánh release. Script bảo vệ 4 lỗi hay gặp:
#   - PR chưa merge vào dev            -> dừng trước khi pick bất kỳ cái nào
#   - PR đã được pick rồi              -> bỏ qua, không tạo commit trùng
#   - nhập số PR lộn xộn               -> tự sắp theo thứ tự merge trên dev
#   - conflict giữa chừng              -> dừng, để nguyên trạng thái cherry-pick cho người resolve
#
# Script KHÔNG push. Xem lại rồi tự đẩy: git push origin <release-branch>
#
# Usage:   bash scripts/release/pick-to-release.sh <release-branch> <pr_number_or_sha>...
# Example: bash scripts/release/pick-to-release.sh release/v1.2.0 3931 3940
#
# Biến môi trường:
#   DEV_REF     nhánh tích hợp (mặc định: origin/dev, fallback dev)
#   NO_FETCH=1  không fetch origin (dùng trong test offline)
# ==============================================================================

set -euo pipefail

RELEASE_BRANCH="${1:-}"
shift || true
if [[ -z "$RELEASE_BRANCH" || $# -eq 0 ]]; then
  echo "Usage: $0 <release-branch> <pr_number_or_sha>..." >&2
  exit 2
fi

[[ "${NO_FETCH:-}" == "1" ]] || git fetch --quiet origin 2>/dev/null || true

DEV_BRANCH="${DEV_REF:-}"
if [[ -z "$DEV_BRANCH" ]]; then
  if git rev-parse --verify --quiet origin/dev >/dev/null; then DEV_BRANCH=origin/dev
  elif git rev-parse --verify --quiet dev >/dev/null; then DEV_BRANCH=dev
  else echo "Error: dev branch not found (set DEV_REF)." >&2; exit 2; fi
fi

git rev-parse --verify --quiet "$RELEASE_BRANCH^{commit}" >/dev/null \
  || git rev-parse --verify --quiet "origin/$RELEASE_BRANCH^{commit}" >/dev/null \
  || { echo "Error: branch '$RELEASE_BRANCH' not found." >&2; exit 2; }

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Error: working tree not clean — commit hoặc stash trước khi pick." >&2
  exit 2
fi

# --- resolve every item BEFORE touching the branch --------------------------
SHAS=()
for item in "$@"; do
  sha=""
  if git rev-parse --verify --quiet "$item^{commit}" >/dev/null && [[ ${#item} -ge 7 ]]; then
    sha="$(git rev-parse "$item^{commit}")"
  else
    pr="${item#\#}"
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "Error: '$item' is neither a PR number nor a commit." >&2; exit 2; }
    # squash-merge subject ends with "(#NNNN)"
    sha="$(git log "$DEV_BRANCH" --format=%H --grep="(#$pr)\$" -n 1)"
    if [[ -z "$sha" ]] && command -v gh >/dev/null 2>&1; then
      sha="$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid // empty' 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$sha" ]]; then
    echo "Error: PR/commit '$item' chưa merge vào $DEV_BRANCH — dừng, không pick gì." >&2
    exit 1
  fi
  if ! git merge-base --is-ancestor "$sha" "$DEV_BRANCH"; then
    echo "Error: commit $sha ($item) không nằm trên $DEV_BRANCH — dừng, không pick gì." >&2
    exit 1
  fi
  SHAS+=("$sha")
done

# --- dedupe + order by merge order on dev -----------------------------------
ORDERED=()
while IFS= read -r sha; do
  for want in "${SHAS[@]}"; do
    if [[ "$want" == "$sha" ]]; then ORDERED+=("$sha"); break; fi
  done
done < <(git rev-list --reverse "$DEV_BRANCH")

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
if [[ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]]; then
  git checkout --quiet "$RELEASE_BRANCH"
fi

PICKED=0; SKIPPED=0
for sha in "${ORDERED[@]}"; do
  subj="$(git log -1 --format=%s "$sha")"
  if git log --format=%H --grep="cherry picked from commit $sha" -n 1 | grep -q .; then
    echo "skip  $(git rev-parse --short "$sha")  $subj  (đã pick trước đó)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  echo "pick  $(git rev-parse --short "$sha")  $subj"
  if ! git cherry-pick -x "$sha"; then
    echo "" >&2
    echo "CONFLICT tại $sha. Resolve rồi: git cherry-pick --continue  (hoặc --abort)." >&2
    echo "Sau đó chạy lại script với các PR còn lại." >&2
    exit 1
  fi
  PICKED=$((PICKED + 1))
done

echo ""
echo "Xong: $PICKED picked, $SKIPPED skipped trên $RELEASE_BRANCH (chưa push)."
echo "  kiểm tra: bash scripts/release/audit-pick.sh $RELEASE_BRANCH"
echo "  đẩy lên : git push origin $RELEASE_BRANCH"
