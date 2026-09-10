#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Audit Pick Gate
#
# Liệt kê mọi PR đã merge vào dev kể từ base của nhánh release và xếp vào 3 nhóm:
#   PICKED   commit đã có trên release (trailer "cherry picked from commit <sha>",
#            fallback so patch-id bằng `git cherry`) và chưa bị revert
#   HOLD     PR có nhãn hold:vX.Y.Z (hoặc .git/holds/vX.Y.Z/<pr> khi test offline)
#   UNKNOWN  còn lại — chưa ai quyết. Có UNKNOWN thì exit 1 (gate chặn tag).
#
# Usage:   bash scripts/release/audit-pick.sh <release-branch> [--md]
# Example: bash scripts/release/audit-pick.sh release/v1.2.0 --md
#
# Biến môi trường:
#   DEV_REF   nhánh tích hợp (mặc định: dev, fallback origin/dev)
# ==============================================================================

set -euo pipefail

RELEASE_ARG="${1:-}"
OUTPUT_MODE="${2:-}"

if [[ -z "$RELEASE_ARG" ]]; then
  echo "Usage: $0 <release-branch> [--md]" >&2
  exit 2
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: not a git repository." >&2; exit 2; }

# Resolve refs: prefer local, fallback origin/
resolve_ref() {
  local ref="$1"
  if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then echo "$ref"; return; fi
  if git rev-parse --verify --quiet "origin/$ref^{commit}" >/dev/null; then echo "origin/$ref"; return; fi
  return 1
}

RELEASE_BRANCH="$(resolve_ref "$RELEASE_ARG")" || { echo "Error: branch '$RELEASE_ARG' not found locally or on origin." >&2; exit 2; }
DEV_BRANCH="$(resolve_ref "${DEV_REF:-dev}")" || { echo "Error: dev branch not found (set DEV_REF)." >&2; exit 2; }

# release/v1.2.0 -> v1.2.0
RELEASE_VERSION="$(sed -n -E 's#.*release/(v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?)$#\1#p' <<< "$RELEASE_ARG")"
if [[ -z "$RELEASE_VERSION" ]]; then
  echo "Error: '$RELEASE_ARG' is not release/vX.Y.Z — cannot derive hold label." >&2
  exit 2
fi
HOLD_LABEL="hold:$RELEASE_VERSION"

MERGE_BASE="$(git merge-base "$RELEASE_BRANCH" "$DEV_BRANCH" 2>/dev/null || true)"
[[ -n "$MERGE_BASE" ]] || { echo "Error: no merge-base between $RELEASE_BRANCH and $DEV_BRANCH." >&2; exit 2; }

BASE_TAG="$(git describe --tags --abbrev=0 "$MERGE_BASE" 2>/dev/null || git rev-parse --short "$MERGE_BASE")"
DEV_HEAD_SHORT="$(git rev-parse --short "$DEV_BRANCH")"
DATE_NOW="$(date "+%Y-%m-%d %H:%M")"

# Hold labels: one gh call for the whole release (no per-PR API call). Empty if gh/network unavailable.
HOLD_PRS=" "
if command -v gh >/dev/null 2>&1; then
  HOLD_PRS=" $( { gh pr list --state merged --label "$HOLD_LABEL" --limit 500 --json number --jq '.[].number' 2>/dev/null || true; } | tr '\n' ' ') "
fi

is_hold() {
  local pr="$1"
  [[ "$pr" == "—" ]] && return 1
  [[ "$HOLD_PRS" == *" $pr "* ]] && return 0
  [[ -f ".git/holds/${RELEASE_VERSION}/${pr}" ]] && return 0
  return 1
}

# Returns 0 if commit is on release (trailer or patch-id) and not reverted afterwards.
is_picked() {
  local sha="$1"
  local picked_sha=""
  picked_sha="$(git log "$RELEASE_BRANCH" --format=%H --grep="cherry picked from commit $sha" -n 1)"
  if [[ -n "$picked_sha" ]]; then
    # reverted on release? (`git revert` writes "This reverts commit <picked sha>")
    if git log "$RELEASE_BRANCH" --format=%H --grep="This reverts commit $picked_sha" -n 1 | grep -q .; then
      return 1
    fi
    return 0
  fi
  # patch-id fallback (pick tay không -x): "- <sha>" = patch tương đương đã có trên release.
  # git cherry tự loại patch đã bị revert (patch + revert triệt tiêu nhau).
  git cherry "$RELEASE_BRANCH" "$sha" "$sha^" 2>/dev/null | grep -q "^- $sha"
}

TOTAL=0; PICKED_COUNT=0; HOLD_COUNT=0; UNKNOWN_COUNT=0
ROWS=()
UNKNOWN_PRS=()

while IFS='|' read -r sha subj; do
  [[ -n "$sha" ]] || continue
  TOTAL=$((TOTAL + 1))

  # squash-merge subject ends with "(#NNNN)"; anything else is a commit without PR
  pr="$(sed -n -E 's/.*\(#([0-9]+)\)$/\1/p' <<< "$subj")"
  [[ -n "$pr" ]] || pr="—"

  type="$(sed -n -E 's/^([a-z]+)(\(.*\))?!?:.*/\1/p' <<< "$subj")"
  [[ -n "$type" ]] || type="?"

  body="$(git log -1 --format=%b "$sha")"
  issue="$(sed -n -E 's/.*(close|closes|closed|fix|fixes|fixed|resolve|resolves|issue|ref)[ :]+#([0-9]+).*/\2/Ip' <<< "$body" | head -n 1)"
  [[ -n "$issue" ]] && issue="#$issue" || issue="—"

  if is_picked "$sha"; then
    status="PICKED"; PICKED_COUNT=$((PICKED_COUNT + 1))
  elif is_hold "$pr"; then
    status="HOLD"; HOLD_COUNT=$((HOLD_COUNT + 1))
  else
    status="UNKNOWN"; UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    UNKNOWN_PRS+=("$([[ "$pr" == "—" ]] && echo "$sha" || echo "$pr")")
  fi

  title="$subj"
  [[ ${#title} -gt 48 ]] && title="${title:0:45}..."
  label="#$pr"; [[ "$pr" == "—" ]] && label="$(git rev-parse --short "$sha") (no PR)"
  ROWS+=("$TOTAL|$label $title|$type|$issue|$status")
done < <(git log --reverse --format='%H|%s' "${MERGE_BASE}..${DEV_BRANCH}")

GATE_STATUS="✅ OK to tag"
[[ $UNKNOWN_COUNT -eq 0 ]] || GATE_STATUS="⛔ chưa được tag"

if [[ "$OUTPUT_MODE" == "--md" ]]; then
  echo "## Release $RELEASE_VERSION — audit pick · $DATE_NOW"
  echo "base \`$BASE_TAG\` → dev @ \`$DEV_HEAD_SHORT\` · $TOTAL PR · $PICKED_COUNT PICKED · $HOLD_COUNT HOLD · **$UNKNOWN_COUNT UNKNOWN** $GATE_STATUS"
  echo
  echo "| # | PR | Loại | Issue | Trạng thái |"
  echo "|---|---|---|---|---|"
  for row in "${ROWS[@]}"; do
    IFS='|' read -r i prcol type issue status <<< "$row"
    echo "| $i | $prcol | $type | $issue | $status |"
  done
  if [[ $UNKNOWN_COUNT -gt 0 ]]; then
    echo
    echo '```'
    echo "pick → bash scripts/release/pick-to-release.sh $RELEASE_ARG ${UNKNOWN_PRS[*]}"
    echo "hold → bash scripts/release/hold-pr.sh $RELEASE_VERSION <pr...>"
    echo '```'
  fi
else
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
  echo "${BOLD}Audit pick — $RELEASE_VERSION${NC} ($DATE_NOW)  base $BASE_TAG → dev @ $DEV_HEAD_SHORT"
  echo "$TOTAL PR · $PICKED_COUNT PICKED · $HOLD_COUNT HOLD · $UNKNOWN_COUNT UNKNOWN"
  printf '%-3s %-56s %-8s %-7s %s\n' '#' 'PR' 'Loại' 'Issue' 'Trạng thái'
  for row in "${ROWS[@]}"; do
    IFS='|' read -r i prcol type issue status <<< "$row"
    color="$RED"; [[ "$status" == PICKED ]] && color="$GREEN"; [[ "$status" == HOLD ]] && color="$YELLOW"
    printf '%-3s %-56s %-8s %-7s %s%s%s\n' "$i" "$prcol" "$type" "$issue" "$color" "$status" "$NC"
  done
  if [[ $UNKNOWN_COUNT -gt 0 ]]; then
    echo "${RED}${BOLD}GATE BLOCKED${NC} — $UNKNOWN_COUNT PR UNKNOWN, không được tag."
    echo "  pick → bash scripts/release/pick-to-release.sh $RELEASE_ARG ${UNKNOWN_PRS[*]}"
    echo "  hold → bash scripts/release/hold-pr.sh $RELEASE_VERSION <pr...>"
  else
    echo "${GREEN}${BOLD}GATE PASSED${NC} — mọi PR đã PICKED hoặc HOLD."
  fi
fi

[[ $UNKNOWN_COUNT -eq 0 ]]
