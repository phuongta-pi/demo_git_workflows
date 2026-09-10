#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Test matrix cho scripts/release (sandbox git, offline)
#
# Mỗi case ASSERT exit code / số đếm của audit-pick; sai là fail (exit 1).
#
#   TC-1  chore + fix pick sớm                        -> PICKED
#   TC-2  pick không theo thứ tự + pick trùng          -> tự sắp, skip trùng
#   TC-3  QC reject trên dev -> hold                   -> HOLD
#   TC-4  PR bị quên                                   -> UNKNOWN, audit exit 1, tag-release từ chối
#   TC-5  QC reject trên staging -> revert + hold      -> HOLD (không phải PICKED)
#   TC-6  fix thẳng trên release, back-port dev        -> PICKED (patch-id, không có trailer)
#   TC-7  0 UNKNOWN                                    -> audit exit 0, tag-release tạo tag
#   TC-8  hotfix từ tag                                -> nhánh đúng base
#   TC-9  pick PR chưa merge dev                       -> exit 1, không đụng nhánh
#   TC-10 cut-release khi đợt trước chưa tag           -> exit 1; --force thì được
#
# Usage: bash scripts/test-workflow-cases.sh
# ==============================================================================

set -euo pipefail
export NO_FETCH=1

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="$(mktemp -d -t picare-test-XXXXXX)"
trap 'cd "$PROJECT_ROOT"; rm -rf "$SIM_DIR"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
assert_eq() { [[ "$2" == "$3" ]] && ok "$1" || fail "$1 (expected '$3', got '$2')"; }
# audit summary line -> "PICKED HOLD UNKNOWN"
audit_counts() {
  bash scripts/release/audit-pick.sh "$1" --md 2>/dev/null | sed -n -E 's/.*· ([0-9]+) PICKED · ([0-9]+) HOLD · \*\*([0-9]+) UNKNOWN\*\*.*/\1 \2 \3/p'
}
audit_rc() { bash scripts/release/audit-pick.sh "$1" --md >/dev/null 2>&1 && echo 0 || echo $?; }
commit_pr() { # <file> <subject> [body]
  echo "$RANDOM" >> "$1"; git add "$1"; git commit -q -m "$2" ${3:+-m "$3"}
}

cd "$SIM_DIR"
git init -q -b main
git config user.name "PiCare Test"; git config user.email "test@picare.vn"
mkdir -p scripts/release && cp "$PROJECT_ROOT"/scripts/release/*.sh scripts/release/

echo "# PiCare" > README.md; git add README.md; git commit -q -m "chore: baseline"
git tag -a v1.1.2 -m "Release v1.1.2"
git checkout -q -b dev
commit_pr tooling.js "chore(config): nâng cấp tooling (#4001)"
commit_pr auth.js    "fix(auth): timeout xác thực (#4002)" "Closes #3201"
commit_pr night.js   "feat(parking): phí đỗ xe đêm (#4003)" "Issue #3250"
commit_pr vip.js     "feat(fee): chiết khấu VIP (#4004)"
commit_pr notify.js  "feat(notify): Zalo ZNS (#4005)" "Closes #3310"

echo "== cut release/v1.2.0 (lần 2+, từ tag v1.1.2)"
bash scripts/release/cut-release.sh v1.2.0 >/dev/null
assert_eq "TC-0 base = v1.1.2" "$(git rev-parse release/v1.2.0)" "$(git rev-parse 'v1.1.2^{commit}')"
assert_eq "TC-0 audit ban đầu: 5 UNKNOWN" "$(audit_counts release/v1.2.0)" "0 0 5"

echo "== TC-1 pick chore + fix"
bash scripts/release/pick-to-release.sh release/v1.2.0 4001 4002 >/dev/null
assert_eq "TC-1 2 PICKED" "$(audit_counts release/v1.2.0)" "2 0 3"

echo "== TC-2 pick lộn thứ tự + trùng"
out="$(bash scripts/release/pick-to-release.sh release/v1.2.0 4005 4001 4005)"
assert_eq "TC-2 4001 bị skip (đã pick)" "$(grep -c '^skip' <<< "$out")" "1"
assert_eq "TC-2 4005 pick đúng 1 lần" "$(git log release/v1.2.0 --oneline | grep -c '#4005')" "1"
assert_eq "TC-2 3 PICKED" "$(audit_counts release/v1.2.0)" "3 0 2"

echo "== TC-3 QC reject trên dev -> hold #4003"
mkdir -p .git/holds/v1.2.0 && touch .git/holds/v1.2.0/4003
assert_eq "TC-3 1 HOLD" "$(audit_counts release/v1.2.0)" "3 1 1"

echo "== TC-4 còn #4004 UNKNOWN -> gate chặn"
assert_eq "TC-4 audit exit 1" "$(audit_rc release/v1.2.0)" "1"
bash scripts/release/tag-release.sh release/v1.2.0 >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "TC-4 tag-release từ chối" "$rc" "1"
assert_eq "TC-4 chưa có tag" "$(git tag -l v1.2.0)" ""
bash scripts/release/pick-to-release.sh release/v1.2.0 4004 >/dev/null
assert_eq "TC-4 sau pick: 0 UNKNOWN" "$(audit_counts release/v1.2.0)" "4 1 0"

echo "== TC-5 QC reject trên staging -> revert #4005 + hold"
git checkout -q release/v1.2.0
git revert --no-edit "$(git log release/v1.2.0 --format=%H --grep='(#4005)' -n 1)" >/dev/null
assert_eq "TC-5 sau revert: #4005 về UNKNOWN" "$(audit_counts release/v1.2.0)" "3 1 1"
touch .git/holds/v1.2.0/4005
assert_eq "TC-5 hold -> 0 UNKNOWN" "$(audit_counts release/v1.2.0)" "3 2 0"

echo "== TC-6 fix thẳng trên release, back-port dev (không trailer)"
commit_pr auth.js "fix(auth): chỉnh margin token trên staging"
stg_fix="$(git rev-parse HEAD)"
git checkout -q dev && git cherry-pick "$stg_fix" >/dev/null   # cố ý không -x
assert_eq "TC-6 patch-id fallback -> PICKED" "$(audit_counts release/v1.2.0)" "4 2 0"

echo "== TC-7 gate pass -> tag"
git checkout -q release/v1.2.0
bash scripts/release/tag-release.sh release/v1.2.0 "Release v1.2.0" >/dev/null
assert_eq "TC-7 tag v1.2.0 tại release HEAD" "$(git rev-parse 'v1.2.0^{commit}')" "$(git rev-parse release/v1.2.0)"

echo "== TC-8 hotfix từ tag"
bash scripts/release/create-hotfix.sh auth-patch >/dev/null
assert_eq "TC-8 nhánh hotfix/auth-patch base v1.2.0" "$(git rev-parse HEAD)" "$(git rev-parse 'v1.2.0^{commit}')"
git checkout -q dev

echo "== TC-9 pick PR chưa merge"
head_before="$(git rev-parse release/v1.2.0)"
bash scripts/release/pick-to-release.sh release/v1.2.0 4001 9999 >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "TC-9 exit 1" "$rc" "1"
assert_eq "TC-9 release không đổi" "$(git rev-parse release/v1.2.0)" "$head_before"

echo "== TC-10 cut đợt mới khi đợt trước chưa tag"
git checkout -q dev
git remote add origin "$SIM_DIR" 2>/dev/null; git fetch -q origin   # origin/release/* để cut-release kiểm tra
git tag -d v1.2.0 >/dev/null                                        # giả lập v1.2.0 chưa lên prod
bash scripts/release/cut-release.sh v1.3.0 >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "TC-10 từ chối (v1.2.0 chưa tag)" "$rc" "1"
bash scripts/release/cut-release.sh v1.3.0 --force >/dev/null
assert_eq "TC-10 --force tạo được" "$(git rev-parse --abbrev-ref HEAD)" "release/v1.3.0"

echo ""
echo "PASS $PASS · FAIL $FAIL"
[[ $FAIL -eq 0 ]]
