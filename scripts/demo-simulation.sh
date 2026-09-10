#!/usr/bin/env bash
# ==============================================================================
# PiCare Git Workflow - Interactive End-to-End Simulation
# Demonstrates the complete lifecycle:
#   1. Dev feature branches & squash PRs to dev
#   2. Cutting release/v1.2.0 (from latest tag v1.1.2)
#   3. Audit Pick Gate (failing with UNKNOWN PRs)
#   4. Cherry-picking approved PRs & setting HOLD labels
#   5. Audit Pick Gate (passing with 0 UNKNOWN)
#   6. Tagging release v1.2.0
#   7. Hotfix flow from tag -> PR to release & backport to dev
# ==============================================================================

set -eo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "================================================================================"
echo "    🚀 PiCare Git Workflow Simulation — Complete End-to-End Walkthrough"
echo "================================================================================"
echo -e "${NC}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Temporary simulation directory
SIM_DIR=$(mktemp -d -t picare-sim-XXXXXX)
cleanup() {
  cd "$PROJECT_ROOT" || true
  rm -rf "$SIM_DIR"
}
trap cleanup EXIT

echo "📁 Tạo sandbox repository tại: $SIM_DIR"
cd "$SIM_DIR"

git init -b main >/dev/null 2>&1
git config user.name "PiCare Bot"
git config user.email "bot@picare.vn"

# Copy project scripts
mkdir -p scripts/release
cp -r "$PROJECT_ROOT/scripts/release"/* scripts/release/
chmod +x scripts/release/*.sh

# Step 1: Base setup
echo -e "\n${BOLD}[Bước 1] Khởi tạo commit gốc và tag prod trước đó (v1.1.2)${NC}"
echo "# PiCare Service" > README.md
git add README.md
git commit -m "chore: initial commit on main" >/dev/null 2>&1
git tag -a "v1.1.2" -m "Release v1.1.2"

# Create dev branch
git checkout -b dev >/dev/null 2>&1
echo "✅ Đã tạo nhánh 'dev' từ tag 'v1.1.2'."

# Step 2: Simulate 5 merged PRs on dev
echo -e "\n${BOLD}[Bước 2] Mô phỏng 5 PR được merge vào nhánh 'dev' (squash merge)${NC}"

# PR 1
echo "console.log('AppCheck enforced');" >> app.js
git add app.js
git commit -m "fix(auth): enforce App Check (#3892)

Closes #3139" >/dev/null 2>&1
echo "  ✓ PR #3892 fix(auth): enforce App Check"

# PR 2
echo "console.log('Car parking fees');" >> parking.js
git add parking.js
git commit -m "feat(parking): biểu phí ô tô (#3916)

Issue: #3952" >/dev/null 2>&1
echo "  ✓ PR #3916 feat(parking): biểu phí ô tô"

# PR 3
echo "console.log('Maintenance fee phase 2');" >> fee.js
git add fee.js
git commit -m "feat(fee): TBP đợt 2 (#3925)

Issue #3900" >/dev/null 2>&1
echo "  ✓ PR #3925 feat(fee): TBP đợt 2"

# PR 4
echo "console.log('Nx 22 upgrade');" >> nx.json
git add nx.json
git commit -m "chore: upgrade nx 22 (#3931)" >/dev/null 2>&1
echo "  ✓ PR #3931 chore: upgrade nx 22"

# PR 5
echo "console.log('Admin filter fix');" >> admin.js
git add admin.js
git commit -m "fix(admin): filter không refill (#3940)

fixes #3938" >/dev/null 2>&1
echo "  ✓ PR #3940 fix(admin): filter không refill"

# Step 3: Leader cuts release/v1.2.0
echo -e "\n${BOLD}[Bước 3] Leader cắt nhánh release/v1.2.0 (Lần 2+: cắt từ tag v1.1.2)${NC}"
bash scripts/release/cut-release.sh v1.2.0

# Step 4: Run Audit Pick (Expected to FAIL with 5 UNKNOWN)
echo -e "\n${BOLD}[Bước 4] Leader chạy Audit Pick trước khi test/tag đợt release${NC}"
set +e
bash scripts/release/audit-pick.sh release/v1.2.0 --md > report_initial.md
AUDIT_EXIT=$?
set -e

cat report_initial.md

if [[ $AUDIT_EXIT -ne 0 ]]; then
  echo -e "\n${RED}==> Audit Pick Gate chặn tag đúng như thiết kế (Exit Code: $AUDIT_EXIT)${NC}"
  echo "    Hiện tại có 5 PR UNKNOWN, Leader không được phép tag release!"
fi

# Step 5: Leader and Dev resolve PRs
echo -e "\n${BOLD}[Bước 5] Leader và Dev xử lý các PR theo quy tắc mặc định:${NC}"
echo "  - Pick chore & bugfix sớm: #3892, #3931, #3940"
echo "  - Pick tính năng ô tô theo scope đợt: #3916"
echo "  - Tính năng phí TBP đợt 2 (#3925) dời sang đợt sau -> Gắn nhãn hold:v1.2.0"

bash scripts/release/pick-to-release.sh release/v1.2.0 3892 3916 3931 3940

# Mark hold for #3925
mkdir -p .git/holds/v1.2.0
touch .git/holds/v1.2.0/3925
echo "  ✓ Đã gắn nhãn hold:v1.2.0 cho PR #3925 (Tương đương: gh pr edit 3925 --add-label hold:v1.2.0)"

# Step 6: Run Audit Pick Again (Expected to PASS)
echo -e "\n${BOLD}[Bước 6] Leader chạy lại Audit Pick Gate:${NC}"
bash scripts/release/audit-pick.sh release/v1.2.0 --md > report_final.md
cat report_final.md

echo -e "\n${GREEN}==> Audit Pick Gate PASSED: 4 PR PICKED, 1 PR HOLD, 0 UNKNOWN!${NC}"

# Step 7: QC Pass -> Leader Tags Release
echo -e "\n${BOLD}[Bước 7] QC xác nhận Pass trên Staging -> Leader đóng Tag v1.2.0${NC}"
bash scripts/release/tag-release.sh release/v1.2.0 "Release v1.2.0 verified by QC"

# Step 8: Hotfix flow demonstration
echo -e "\n${BOLD}[Bước 8] Mô phỏng sự cố Prod và quy trình Hotfix:${NC}"
bash scripts/release/create-hotfix.sh urgent-login v1.2.0
echo "console.log('Hotfix critical login');" >> app.js
git add app.js
git commit -m "fix(auth): fix urgent login deadlock on prod" >/dev/null 2>&1
echo "  ✓ Đã commit bản sửa lỗi trên nhánh hotfix/urgent-login"

echo "  ✓ Đưa hotfix vào release/v1.2.0 (để QC test staging):"
git checkout release/v1.2.0 >/dev/null 2>&1
git cherry-pick -x hotfix/urgent-login >/dev/null 2>&1
echo "    -> Đã merge hotfix vào release/v1.2.0"

echo "  ✓ Backport hotfix về nhánh dev (để không thất lạc code):"
git checkout dev >/dev/null 2>&1
git cherry-pick -x hotfix/urgent-login >/dev/null 2>&1
echo "    -> Đã backport hotfix vào dev"

echo -e "\n${GREEN}${BOLD}================================================================================"
echo "    🎉 Toàn bộ chu trình PiCare Git Workflow đã được mô phỏng thành công!"
echo "================================================================================${NC}"
