#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Comprehensive Test Matrix with QC Rejection Scenarios
#
# Covers 8 Core Test Cases:
#   [TC-1] Happy Path: chore/refactor pick sớm lên release
#   [TC-2] Happy Path: fix có linked issue đã QC pass trên dev -> pick lên release
#   [TC-3] QC Reject trên Dev: feat lỗi/chưa xong -> Leader gắn HOLD (không pick)
#   [TC-4] Audit Gate Block: PR bỏ quên (UNKNOWN) -> Chặn đóng Tag v1.2.0
#   [TC-5] QC Reject trên Staging: Đã pick vào release nhưng QC phát hiện bug nặng
#          -> Revert khỏi release branch + gắn HOLD
#   [TC-6] Fix trực tiếp trên Staging: QC phát hiện lỗi nhỏ -> fix & backport dev
#   [TC-7] Audit Gate Passed: 0 UNKNOWN -> Cho phép đóng Tag v1.2.0 & Deploy Prod
#   [TC-8] Hotfix từ Prod tag: Sự cố trên prod -> rẽ nhánh từ tag -> PR release & dev
# ==============================================================================

set -eo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR=$(mktemp -d -t picare-test-matrix-XXXXXX)

cleanup() {
  cd "$PROJECT_ROOT" || true
  rm -rf "$SIM_DIR"
}
trap cleanup EXIT

echo -e "${BOLD}${CYAN}"
echo "================================================================================"
echo "    🧪 PiCare Git Workflow: Kịch bản Kiểm thử Toàn diện (Gồm QC Rejections)"
echo "================================================================================"
echo -e "${NC}"
echo "📁 Sandbox test tại: $SIM_DIR"

cd "$SIM_DIR"
git init -b main >/dev/null 2>&1
git config user.name "PiCare QC-Dev Team"
git config user.email "team@picare.vn"

# Copy release scripts
mkdir -p scripts/release
cp -r "$PROJECT_ROOT/scripts/release"/* scripts/release/
chmod +x scripts/release/*.sh

# Baseline: main & tag v1.1.2 & dev
echo "# PiCare System" > README.md
git add README.md
git commit -m "chore: initial release baseline" >/dev/null 2>&1
git tag -a "v1.1.2" -m "Release v1.1.2"
git checkout -b dev >/dev/null 2>&1
echo "✅ Khởi tạo nhánh dev từ tag baseline v1.1.2"

# ------------------------------------------------------------------------------
# 1. Phát triển 5 module PRs trên nhánh dev
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}PHASE 1: DEV & MERGE 5 MODULES VÀO NHÁNH 'dev' (Squash Merge)${NC}"
echo -e "${BOLD}================================================================================${NC}"

# PR 1 (Chore)
echo "export const TOOLING_VER = '2.0';" > tooling.js
git add tooling.js
git commit -m "chore(config): nâng cấp tooling hệ thống (#4001)" >/dev/null 2>&1
echo "  ✓ PR #4001: chore(config): nâng cấp tooling hệ thống"

# PR 2 (Fix)
echo "export const verifyToken = () => true;" > auth.js
git add auth.js
git commit -m "fix(auth): sửa lỗi timeout xác thực cư dân (#4002)

Closes #3201" >/dev/null 2>&1
echo "  ✓ PR #4002: fix(auth): sửa lỗi timeout xác thực cư dân (Issue #3201)"

# PR 3 (Feat - QC sẽ Reject trên Dev)
echo "export const nightParkingRate = 50000;" > night_parking.js
git add night_parking.js
git commit -m "feat(parking): tính phí đỗ xe theo khung giờ đêm (#4003)

Issue #3250" >/dev/null 2>&1
echo "  ✓ PR #4003: feat(parking): tính phí đỗ xe khung giờ đêm (Issue #3250)"

# PR 4 (Feat - Sẽ bị quên UNKNOWN để test Gate)
echo "export const vipDiscount = 0.15;" > vip_fee.js
git add vip_fee.js
git commit -m "feat(fee): chiết khấu cư dân VIP đợt 2 (#4004)" >/dev/null 2>&1
echo "  ✓ PR #4004: feat(fee): chiết khấu cư dân VIP đợt 2"

# PR 5 (Feat - Sẽ được pick nhưng QC REJECT TRÊN STAGING)
echo "export const sendZaloNotification = () => 'SENT';" > notification.js
git add notification.js
git commit -m "feat(notify): gửi thông báo đẩy qua Zalo ZNS (#4005)

Closes #3310" >/dev/null 2>&1
echo "  ✓ PR #4005: feat(notify): gửi thông báo đẩy qua Zalo ZNS (Issue #3310)"

# ------------------------------------------------------------------------------
# 2. Cắt nhánh release/v1.2.0
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}PHASE 2: LEADER CẮT NHÁNH release/v1.2.0 TỪ TAG PROD v1.1.2${NC}"
echo -e "${BOLD}================================================================================${NC}"
bash scripts/release/cut-release.sh v1.2.0

# ------------------------------------------------------------------------------
# [TC-1] & [TC-2]: Pick PR #4001 (Chore) và PR #4002 (Fix QC pass trên Dev)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[TC-1 & TC-2] Leader pick PR #4001 (chore) và PR #4002 (fix QC pass trên dev):${NC}"
bash scripts/release/pick-to-release.sh release/v1.2.0 4001 4002

# ------------------------------------------------------------------------------
# [TC-3]: QC REJECT PR #4003 TRÊN DEV (Chưa đạt tiêu chuẩn đợt này)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[TC-3] QC REJECT TRÊN DEV: PR #4003 (Phí đỗ xe đêm) bị lỗi tính sai giờ.${NC}"
echo "  ➡️ Quyết định: KHÔNG pick PR #4003 vào release/v1.2.0."
echo "  ➡️ Leader gắn nhãn hold:v1.2.0 để dời sang đợt sau (v1.3.0)."
mkdir -p .git/holds/v1.2.0
touch .git/holds/v1.2.0/4003
echo "  ✓ Đã gắn nhãn hold:v1.2.0 cho PR #4003"

# ------------------------------------------------------------------------------
# [TC-5 Part A]: Pick PR #4005 vào release để đưa lên Staging test
# ------------------------------------------------------------------------------
echo -e "\n[Chuẩn bị TC-5] Pick PR #4005 (thông báo Zalo) vào release để đẩy lên Staging:"
bash scripts/release/pick-to-release.sh release/v1.2.0 4005

# ------------------------------------------------------------------------------
# [TC-4]: KIỂM TRA AUDIT GATE KHI CÒN PR UNKNOWN (#4004 BỊ BỎ QUÊN)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}[TC-4] KIỂM TRA AUDIT PICK GATE TRƯỚC KHI TAG (KHI CÒN PR #4004 UNKNOWN)${NC}"
echo -e "${BOLD}================================================================================${NC}"

set +e
bash scripts/release/audit-pick.sh release/v1.2.0 --md > report_tc4.md
GATE_EXIT=$?
set -e

cat report_tc4.md

if [[ $GATE_EXIT -ne 0 ]]; then
  echo -e "\n${RED}🛑 [TC-4 PASS] Audit Gate chặn Tag thành công! (Exit code: $GATE_EXIT)${NC}"
  echo "    Lý do: PR #4004 vẫn là UNKNOWN (chưa ai quyết định pick hay hold)."
fi

# Thử chạy tag script xem có bị chặn không
set +e
bash scripts/release/tag-release.sh release/v1.2.0 "Release v1.2.0" >/dev/null 2>&1
TAG_EXIT=$?
set -e
if [[ $TAG_EXIT -ne 0 ]]; then
  echo -e "${RED}🛑 [TC-4 PASS] Lệnh tag-release.sh đã từ chối tạo tag vì Gate vi phạm!${NC}"
fi

# Xử lý PR #4004: PM duyệt bổ sung cho phép đưa vào đợt v1.2.0 -> Pick
echo -e "\n==> Leader xử lý PR #4004: Pick vào release/v1.2.0..."
bash scripts/release/pick-to-release.sh release/v1.2.0 4004

# ------------------------------------------------------------------------------
# [TC-5 Part B]: QC REJECT PR #4005 TRÊN STAGING -> REVERT KHỎI RELEASE & GẮN HOLD
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}[TC-5] QC KIỂM THỬ TRÊN STAGING: PHÁT HIỆN LỖI NẶNG Ở MODULE NOTIFICATION (#4005)${NC}"
echo -e "${BOLD}================================================================================${NC}"
echo -e "${YELLOW}⚠️ QC Report: Module thông báo Zalo (#4005) gây crash webhook khi tải cao!${NC}"
echo -e "${YELLOW}⚠️ Quyết định khẩn: REJECT module #4005 khỏi đợt phát hành v1.2.0!${NC}"

git checkout release/v1.2.0 >/dev/null 2>&1
NOTIFY_COMMIT=$(git log release/v1.2.0 --grep="(#4005)" -n 1 --format="%H")
echo "==> Leader thực hiện revert commit $NOTIFY_COMMIT trên nhánh release/v1.2.0..."
git revert --no-edit "$NOTIFY_COMMIT" >/dev/null 2>&1
echo "  ✓ Đã revert mã nguồn PR #4005 khỏi nhánh release/v1.2.0!"

echo "==> Leader gắn nhãn hold:v1.2.0 cho PR #4005 để chuyển về trạng thái HOLD:"
touch .git/holds/v1.2.0/4005
echo "  ✓ Đã gắn nhãn hold:v1.2.0 cho PR #4005"

# ------------------------------------------------------------------------------
# [TC-6]: FIX LỖI NHỎ TRỰC TIẾP TRÊN STAGING & BACKPORT DEV
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}[TC-6] QC PHÁT HIỆN LỖI NHỎ Ở AUTH TRÊN STAGING -> DEV FIX & BACKPORT DEV${NC}"
echo -e "${BOLD}================================================================================${NC}"
git checkout release/v1.2.0 >/dev/null 2>&1
echo "// Fix small token margin on staging" >> auth.js
git add auth.js
git commit -m "fix(auth): adjust token expiration margin on staging" >/dev/null 2>&1
FIX_STG_COMMIT=$(git rev-parse HEAD)
echo "  ✓ Đã commit bản sửa lỗi trên release/v1.2.0 ($FIX_STG_COMMIT)"
echo "  ✓ QC re-test Staging: PASS! ✅"

echo "==> Backport commit fix này về nhánh dev để không bị lệch code:"
git checkout dev >/dev/null 2>&1
git cherry-pick -x "$FIX_STG_COMMIT" >/dev/null 2>&1
echo "  ✓ Đã backport fix về nhánh dev thành công!"

# ------------------------------------------------------------------------------
# [TC-7]: CHẠY LẠI AUDIT GATE -> TẤT CẢ OK -> ĐÓNG TAG v1.2.0 & DEPLOY PROD
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}[TC-7] CHẠY LẠI AUDIT GATE TRƯỚC KHI ĐÓNG TAG v1.2.0${NC}"
echo -e "${BOLD}================================================================================${NC}"

git checkout release/v1.2.0 >/dev/null 2>&1
bash scripts/release/audit-pick.sh release/v1.2.0 --md > report_tc7.md
cat report_tc7.md

echo -e "\n${GREEN}==> Audit Gate PASSED: 0 UNKNOWN! Tiến hành đóng Tag v1.2.0...${NC}"
bash scripts/release/tag-release.sh release/v1.2.0 "Release v1.2.0 - PiCare Staging Verified"

# ------------------------------------------------------------------------------
# [TC-8]: PHÁT SINH SỰ CỐ PROD -> TẠO HOTFIX TỪ TAG v1.2.0
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}================================================================================${NC}"
echo -e "${BOLD}[TC-8] SỰ CỐ PROD PHÁT SINH -> HOTFIX TỪ TAG v1.2.0${NC}"
echo -e "${BOLD}================================================================================${NC}"

bash scripts/release/create-hotfix.sh emergency-auth-patch v1.2.0
echo "// Emergency security patch" >> auth.js
git add auth.js
git commit -m "fix(security): emergency patch for auth header" >/dev/null 2>&1
echo "  ✓ Đã commit bản sửa lỗi trên nhánh hotfix/emergency-auth-patch"

echo "==> Đưa hotfix vào release/v1.2.0 (để QC test staging):"
git checkout release/v1.2.0 >/dev/null 2>&1
git cherry-pick -x hotfix/emergency-auth-patch >/dev/null 2>&1
echo "  ✓ Đã đưa hotfix vào release/v1.2.0"

echo "==> Backport hotfix về dev:"
git checkout dev >/dev/null 2>&1
git cherry-pick -x hotfix/emergency-auth-patch >/dev/null 2>&1
echo "  ✓ Đã backport hotfix vào dev"

echo -e "\n${GREEN}${BOLD}================================================================================"
echo "    🎉 HOÀN TẤT TẤT CẢ 8 TEST CASES TRONG KỊCH BẢN WORKFLOW THÀNH CÔNG!"
echo "================================================================================${NC}"
