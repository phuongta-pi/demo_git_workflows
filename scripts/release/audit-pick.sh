#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Audit Pick Gate
# Usage: bash scripts/release/audit-pick.sh <release-branch> [--md]
# Example: bash scripts/release/audit-pick.sh release/v1.2.0 --md
# ==============================================================================

set -eo pipefail

RELEASE_BRANCH="${1:-}"
OUTPUT_MODE="${2:-}"

if [[ -z "$RELEASE_BRANCH" ]]; then
  echo "Error: Release branch argument missing."
  echo "Usage: $0 <release-branch> [--md]"
  echo "Example: $0 release/v1.2.0 --md"
  exit 1
fi

# Ensure git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Must be run inside a git repository."
  exit 1
fi

# Normalize branch name
if ! git rev-parse --verify "$RELEASE_BRANCH" >/dev/null 2>&1; then
  if git rev-parse --verify "origin/$RELEASE_BRANCH" >/dev/null 2>&1; then
    RELEASE_BRANCH="origin/$RELEASE_BRANCH"
  else
    echo "Error: Branch '$RELEASE_BRANCH' not found locally or on origin."
    exit 1
  fi
fi

# Target dev branch (check local or origin)
DEV_BRANCH="dev"
if ! git rev-parse --verify "$DEV_BRANCH" >/dev/null 2>&1; then
  if git rev-parse --verify "origin/dev" >/dev/null 2>&1; then
    DEV_BRANCH="origin/dev"
  else
    # Fallback to current branch or main if dev doesn't exist yet
    DEV_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
  fi
fi

# Extract version string from release branch name (e.g. release/v1.2.0 -> v1.2.0)
RELEASE_VERSION=$(echo "$RELEASE_BRANCH" | sed -E 's/.*release\/(v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?).*/\1/')
if [[ -z "$RELEASE_VERSION" || "$RELEASE_VERSION" == "$RELEASE_BRANCH" ]]; then
  RELEASE_VERSION="v1.2.0"
fi

# Find merge base between release branch and dev
MERGE_BASE=$(git merge-base "$RELEASE_BRANCH" "$DEV_BRANCH" 2>/dev/null || echo "")
if [[ -z "$MERGE_BASE" ]]; then
  echo "Error: Could not find merge-base between $RELEASE_BRANCH and $DEV_BRANCH."
  exit 1
fi

# Check for nearest tag to merge base for readable label
BASE_TAG=$(git describe --tags --abbrev=0 "$MERGE_BASE" 2>/dev/null || echo "$MERGE_BASE" | cut -c1-7)
DEV_HEAD_SHORT=$(git rev-parse --short "$DEV_BRANCH" 2>/dev/null || echo "head")
DATE_NOW=$(date "+%Y-%m-%d %H:%M")

COMMIT_LIST=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  COMMIT_LIST+=("$line")
done < <(git log --reverse --format="%H|%s" "${MERGE_BASE}..${DEV_BRANCH}")

TOTAL_PRS=${#COMMIT_LIST[@]}
PICKED_COUNT=0
HOLD_COUNT=0
UNKNOWN_COUNT=0

declare -a REPORT_ROWS=()
declare -a UNKNOWN_PRS=()

INDEX=1
for ENTRY in "${COMMIT_LIST[@]}"; do
  [[ -z "$ENTRY" ]] && continue
  COMMIT_HASH="${ENTRY%%|*}"
  COMMIT_SUBJ="${ENTRY#*|}"

  # Extract PR number if present: #1234 or (#1234)
  PR_NUM=$(echo "$COMMIT_SUBJ" | sed -n -E 's/.*#([0-9]+).*/\1/p' | head -n 1)
  if [[ -z "$PR_NUM" ]]; then
    PR_NUM="$INDEX"
  fi

  # Extract Type (feat, fix, chore, docs, refactor, etc.)
  PR_TYPE=$(echo "$COMMIT_SUBJ" | sed -n -E 's/^([a-zA-Z]+).*/\1/p')
  if [[ -z "$PR_TYPE" ]]; then
    PR_TYPE="feat"
  fi

  # Extract Issue reference if present (e.g. Issue #1234 or fixes #1234)
  BODY_CONTENT=$(git log -1 --format="%b" "$COMMIT_HASH")
  ISSUE_NUM=$(echo "$BODY_CONTENT" | sed -n -E 's/.*(fix|fixes|close|closes|issue|ref)[ :]+#([0-9]+).*/\2/Ip' | head -n 1)
  if [[ -n "$ISSUE_NUM" ]]; then
    ISSUE_REF="#$ISSUE_NUM"
  else
    ISSUE_REF="—"
  fi

  # Determine Status:
  # 1. PICKED: check trailer `cherry picked from commit <sha>` on release branch
  # or patch equivalence via git cherry
  IS_PICKED=0
  if git log "$RELEASE_BRANCH" --grep="cherry picked from commit $COMMIT_HASH" --oneline | grep -q .; then
    IS_PICKED=1
  elif git log "$RELEASE_BRANCH" --grep="cherry picked from commit $(echo $COMMIT_HASH | cut -c1-7)" --oneline | grep -q .; then
    IS_PICKED=1
  else
    # Fallback to git cherry patch comparison
    CHERRY_CHECK=$(git cherry "$RELEASE_BRANCH" "$COMMIT_HASH" 2>/dev/null | cut -c1 || echo "+")
    if [[ "$CHERRY_CHECK" == "-" ]]; then
      IS_PICKED=1
    fi
  fi

  # 2. HOLD: Check GitHub PR label `hold:<version>` (or git trailer / local label file)
  IS_HOLD=0
  if [[ $IS_PICKED -eq 0 ]]; then
    EXPECTED_LABEL="hold:$RELEASE_VERSION"

    # Check via gh CLI if PR exists and network available
    if command -v gh >/dev/null 2>&1 && [[ -n "$PR_NUM" && "$PR_NUM" =~ ^[0-9]+$ ]]; then
      GH_LABELS=$(gh pr view "$PR_NUM" --json labels --jq '.labels[].name' 2>/dev/null || echo "")
      if echo "$GH_LABELS" | grep -q "^${EXPECTED_LABEL}$"; then
        IS_HOLD=1
      fi
    fi

    # Fallback: check commit body for `Hold: vX.Y.Z` or `.git/holds/<version>/<pr>`
    if [[ $IS_HOLD -eq 0 ]]; then
      if echo "$BODY_CONTENT" | grep -qi "Hold: *$RELEASE_VERSION"; then
        IS_HOLD=1
      elif [[ -f ".git/holds/${RELEASE_VERSION}/${PR_NUM}" ]]; then
        IS_HOLD=1
      fi
    fi
  fi

  STATUS="UNKNOWN"
  if [[ $IS_PICKED -eq 1 ]]; then
    STATUS="PICKED"
    ((PICKED_COUNT++))
  elif [[ $IS_HOLD -eq 1 ]]; then
    STATUS="HOLD"
    ((HOLD_COUNT++))
  else
    STATUS="UNKNOWN"
    ((UNKNOWN_COUNT++))
    UNKNOWN_PRS+=("$PR_NUM")
  fi

  # Clean title for display
  DISPLAY_TITLE="$COMMIT_SUBJ"
  # Truncate if too long
  if [[ ${#DISPLAY_TITLE} -gt 36 ]]; then
    DISPLAY_TITLE="${DISPLAY_TITLE:0:33}..."
  fi

  REPORT_ROWS+=("$INDEX|#$PR_NUM $DISPLAY_TITLE|$PR_TYPE|$ISSUE_REF|$STATUS")
  ((INDEX++))
done

# Format output
GATE_STATUS="✅ OK to tag"
if [[ $UNKNOWN_COUNT -gt 0 ]]; then
  GATE_STATUS="⛔ chưa được tag"
fi

if [[ "$OUTPUT_MODE" == "--md" ]]; then
  cat << EOF
## Release $RELEASE_VERSION — audit pick · $DATE_NOW
base $BASE_TAG → dev @ $DEV_HEAD_SHORT · $TOTAL_PRS PR · $UNKNOWN_COUNT UNKNOWN $GATE_STATUS

| # | PR | Loại | Issue | Trạng thái |
|---|---|---|---|---|
EOF

  for ROW in "${REPORT_ROWS[@]}"; do
    IFS="|" read -r R_IDX R_PR R_TYPE R_ISSUE R_STATUS <<< "$ROW"
    printf "| %s | %-34s | %-5s | %-5s | %-10s |\n" "$R_IDX" "$R_PR" "$R_TYPE" "$R_ISSUE" "$R_STATUS"
  done

  echo ""
  if [[ $UNKNOWN_COUNT -gt 0 ]]; then
    PICK_LIST="${UNKNOWN_PRS[*]}"
    FIRST_UNKNOWN="${UNKNOWN_PRS[0]}"
    cat << EOF
pick → bash scripts/release/pick-to-release.sh $RELEASE_BRANCH $PICK_LIST
hold → gh pr edit $FIRST_UNKNOWN --add-label hold:$RELEASE_VERSION
EOF
  fi
else
  # Terminal colored output
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'

  echo -e "${BOLD}========================================================================${NC}"
  echo -e "${BOLD}PiCare Audit Pick Report — Release $RELEASE_VERSION${NC} ($DATE_NOW)"
  echo -e "base: $BASE_TAG → dev @ $DEV_HEAD_SHORT | Total: $TOTAL_PRS PR | UNKNOWN: $UNKNOWN_COUNT"
  echo -e "${BOLD}========================================================================${NC}"
  printf "%-3s %-40s %-8s %-8s %-10s\n" "#" "PR" "Loại" "Issue" "Trạng thái"
  echo "------------------------------------------------------------------------"

  for ROW in "${REPORT_ROWS[@]}"; do
    IFS="|" read -r R_IDX R_PR R_TYPE R_ISSUE R_STATUS <<< "$ROW"
    COLOR="$RED"
    if [[ "$R_STATUS" == "PICKED" ]]; then COLOR="$GREEN"; fi
    if [[ "$R_STATUS" == "HOLD" ]]; then COLOR="$YELLOW"; fi

    printf "%-3s %-40s %-8s %-8s ${COLOR}%-10s${NC}\n" "$R_IDX" "$R_PR" "$R_TYPE" "$R_ISSUE" "$R_STATUS"
  done

  echo "------------------------------------------------------------------------"
  if [[ $UNKNOWN_COUNT -gt 0 ]]; then
    echo -e "${RED}${BOLD}Gate check FAILED ($GATE_STATUS)${NC}: Không được tag khi còn $UNKNOWN_COUNT PR UNKNOWN."
    echo -e "Để xử lý:"
    echo -e "  - Pick lên release : bash scripts/release/pick-to-release.sh $RELEASE_BRANCH ${UNKNOWN_PRS[*]}"
    echo -e "  - Tạm hoãn sang đợt sau: gh pr edit <pr#> --add-label hold:$RELEASE_VERSION"
  else
    echo -e "${GREEN}${BOLD}Gate check PASSED ($GATE_STATUS)${NC}: Tất cả PR đã PICKED hoặc HOLD."
  fi
fi

# Exit code: 1 if UNKNOWN > 0, 0 if clean
if [[ $UNKNOWN_COUNT -gt 0 ]]; then
  exit 1
else
  exit 0
fi
