# PiCare Git Workflow Demo

Demo codebase hoàn chỉnh hiện thực hóa quy trình **PiCare Git Workflow** với cơ chế kiểm soát phát hành **Audit Pick Gate** và tự động hóa CI/CD cho 3 môi trường Firebase:
- **DEV**: Firebase `picitydev` (nhánh `dev`)
- **STAGING**: Firebase `picarestg` (nhánh `release/vX.Y.Z`)
- **PROD**: Firebase `picareprod` (nhánh Tag `vX.Y.Z` hoặc release do Leader dispatch)

Chi tiết sơ đồ workflow tham chiếu: [PiCare Git Workflow Diagram](https://share.onorca.dev/a/ACZDpelnSN41).

---

## ⚡ Cài đặt & Chạy thử nhanh

### 1. Cài đặt dependencies và kiểm tra code
```bash
npm install
npm run build
npm test
```

### 2. Chạy kịch bản mô phỏng toàn diện (One-command Simulation)
Lệnh sau sẽ khởi tạo môi trường sandbox git độc lập, mô phỏng 5 PR (`feat`, `fix`, `chore`), cắt release, kích hoạt Audit Gate (bị chặn do có UNKNOWN PR), cherry-pick, gắn nhãn hold, vượt qua Gate để đóng Tag, và xử lý luồng Hotfix:
```bash
npm run demo:simulate
```

---

## 📂 Cấu trúc Repository

```
demo_git_workflows/
├── .github/
│   ├── workflows/
│   │   ├── deploy-dev.yml         # Auto deploy Firebase picitydev khi push dev
│   │   ├── deploy-staging.yml     # Auto deploy Firebase picarestg khi push release/**
│   │   ├── deploy-prod.yml        # Deploy Firebase picareprod (có Audit Pick Gate)
│   │   ├── audit-pick.yml         # On-demand Audit Pick Action
│   │   └── pr-checks.yml          # Kiểm tra lint, test, build cho mọi PR
│   └── pull_request_template.md   # Mẫu PR chuẩn hóa
├── .firebaserc                    # Định nghĩa picitydev, picarestg, picareprod
├── firebase.json                  # Cấu hình Firebase hosting & functions
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts                   # Mini API service minh họa
│   ├── config.ts                  # Mapping môi trường & Firebase project
│   ├── modules/
│   │   ├── auth/appCheck.ts       # Mô-đun PR #3892 fix(auth): enforce App Check
│   │   ├── parking/rates.ts       # Mô-đun PR #3916 feat(parking): biểu phí ô tô
│   │   ├── fee/calculation.ts     # Mô-đun PR #3925 feat(fee): TBP đợt 2
│   │   └── admin/filter.ts        # Mô-đun PR #3940 fix(admin): filter không refill
│   └── __tests__/
│       └── app.test.ts            # Test suite đảm bảo chất lượng
├── scripts/
│   ├── release/
│   │   ├── audit-pick.sh          # Script cốt lõi: Audit Pick Gate
│   │   ├── pick-to-release.sh     # Cherry-pick PR vào release với trailer -x
│   │   ├── cut-release.sh         # Cắt release branch (Lần 1: dev, Lần 2+: tag prod)
│   │   ├── tag-release.sh         # Kiểm tra Gate & đóng tag vX.Y.Z
│   │   └── create-hotfix.sh       # Tạo nhánh hotfix từ tag prod
│   └── demo-simulation.sh         # Script kịch bản mô phỏng End-to-End
├── WORKFLOW.md                    # Tài liệu đặc tả quy trình chi tiết
└── README.md
```

---

## 🛠 Bộ công cụ Quản lý Phát hành (Release Scripts)

### 1. Cắt nhánh Release: `scripts/release/cut-release.sh`
Tuân thủ nguyên tắc:
- Lần 1: Cắt từ nhánh `dev`.
- Lần 2+: Cắt từ latest tag prod (ví dụ: `v1.1.2`).
```bash
bash scripts/release/cut-release.sh v1.2.0
```

### 2. Kiểm tra Audit Pick Gate: `scripts/release/audit-pick.sh`
Quét dải commit `merge-base(release, dev)..dev`, phân loại từng PR thành 3 trạng thái:
- `PICKED`: Đã cherry-pick vào release (nhận diện qua trailer `(cherry picked from commit <sha>)` hoặc so khớp patch).
- `HOLD`: Đã hoãn sang đợt sau (nhãn GitHub `hold:vX.Y.Z`).
- `UNKNOWN`: Chưa được quyết định. **Nếu còn UNKNOWN > 0, script exit code 1 và chặn đóng Tag!**

```bash
# Xem báo cáo dạng bảng màu trên terminal
bash scripts/release/audit-pick.sh release/v1.2.0

# Xuất bảng Markdown (cho GitHub Summary / Issue tracking / Orca artifact)
bash scripts/release/audit-pick.sh release/v1.2.0 --md
```

Ví dụ bảng báo cáo:
```markdown
## Release v1.2.0 — audit pick · 2026-09-10 14:59
base v1.1.2 → dev @ 4166af1 · 5 PR · 0 UNKNOWN ✅ OK to tag

| # | PR | Loại | Issue | Trạng thái |
|---|---|---|---|---|
| 1 | #3892 fix(auth): enforce App Check (#3892) | fix   | #3139 | PICKED     |
| 2 | #3916 feat(parking): biểu phí ô tô (#3916) | feat  | #3952 | PICKED     |
| 3 | #3925 feat(fee): TBP đợt 2 (#3925) | feat  | #3900 | HOLD       |
| 4 | #3931 chore: upgrade nx 22 (#3931) | chore | —   | PICKED     |
| 5 | #3940 fix(admin): filter không refill (... | fix   | #3938 | PICKED     |
```

### 3. Cherry-pick PR vào Release: `scripts/release/pick-to-release.sh`
Tự động tìm kiếm commit SHA từ số hiệu PR trên nhánh `dev` và thực hiện `git cherry-pick -x`:
```bash
bash scripts/release/pick-to-release.sh release/v1.2.0 3892 3916 3940
```

### 4. Đóng Tag phát hành: `scripts/release/tag-release.sh`
Tự động chạy `audit-pick.sh` trước. Nếu có PR UNKNOWN sẽ lập tức chặn; nếu đạt 0 UNKNOWN sẽ tạo annotated git tag:
```bash
bash scripts/release/tag-release.sh release/v1.2.0 "Release v1.2.0"
```

### 5. Xử lý Hotfix: `scripts/release/create-hotfix.sh`
Tạo nhánh hotfix từ tag prod gần nhất. Sau khi sửa lỗi:
1. Mở PR vào nhánh `release/vX.Y.Z` (để QC test staging).
2. Mở PR backport vào nhánh `dev`.
```bash
bash scripts/release/create-hotfix.sh fix-urgent-login v1.2.0
```

---

## 📖 Tài liệu chuyên sâu
Xem toàn bộ đặc tả quy trình và ma trận trách nhiệm Dev / QC / Leader tại [WORKFLOW.md](file:///Users/admin/orca/demo_git_workflows/WORKFLOW.md).
