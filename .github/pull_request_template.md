## Mô tả thay đổi (Description)
<!-- Tóm tắt ngắn gọn các thay đổi trong PR này -->

## Loại PR (PR Type)
<!-- Chọn một trong các loại sau: -->
- [ ] `feat`: Tính năng mới (Cần PM duyệt scope đợt)
- [ ] `fix`: Sửa lỗi (Linked issue đã QC pass trên dev)
- [ ] `chore`: Cải tiến tooling / refactor (Pick sớm lên release)
- [ ] `docs`: Tài liệu / typo (Pick sớm)

## Liên kết Issue (Linked Issue)
<!-- Ví dụ: Closes #3139 hoặc Fixes #3952 -->
Closes #

## Hướng dẫn kiểm thử (Testing Instructions)
1. Bước 1...
2. Bước 2...

## Nhắc nhở quy trình PiCare Release Audit
- [ ] PR đã được merge squash vào `dev`.
- [ ] Nếu là `feat` chưa ra đợt này, Leader gắn nhãn `hold:vX.Y.Z`.
- [ ] Nếu cần pick vào release: `bash scripts/release/pick-to-release.sh release/vX.Y.Z <PR#>`
