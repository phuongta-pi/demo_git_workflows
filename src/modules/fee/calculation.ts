/**
 * Fee Module: TBP đợt 2 (Tiền bảo trì căn hộ & dịch vụ đợt 2)
 * PR #3925 - feat(fee): TBP đợt 2 (Issue #3900)
 */

export interface MaintenanceFeeParams {
  apartmentAreaM2: number;
  ratePerM2VND: number;
  discountRate?: number; // 0.0 to 1.0
  phase: 1 | 2;
}

export function calculateMaintenanceFee(params: MaintenanceFeeParams): number {
  const base = params.apartmentAreaM2 * params.ratePerM2VND;
  const phaseMultiplier = params.phase === 2 ? 1.05 : 1.0; // Đợt 2 áp dụng hệ số điều chỉnh dịch vụ
  const subtotal = base * phaseMultiplier;
  const discount = subtotal * (params.discountRate || 0);
  return Math.round(subtotal - discount);
}
