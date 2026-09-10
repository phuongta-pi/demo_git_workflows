/**
 * Facility Module: Quản lý đặt chỗ tiện ích nội khu PiCare
 * feat(facility): biểu phí và tính cước đặt tiện ích (Issue #3)
 */

export type FacilityType = 'bbq_area' | 'tennis_court' | 'swimming_pool' | 'community_hall';

export interface FacilityRate {
  type: FacilityType;
  name: string;
  baseHourlyRateVND: number;
  maxHoursPerSlot: number;
  peakHourMultiplier: number;
}

export const FACILITY_RATES: Record<FacilityType, FacilityRate> = {
  bbq_area: {
    type: 'bbq_area',
    name: 'Khu tiệc nướng BBQ ngoài trời',
    baseHourlyRateVND: 100000,
    maxHoursPerSlot: 4,
    peakHourMultiplier: 1.25,
  },
  tennis_court: {
    type: 'tennis_court',
    name: 'Sân Tennis tiêu chuẩn',
    baseHourlyRateVND: 80000,
    maxHoursPerSlot: 3,
    peakHourMultiplier: 1.2,
  },
  swimming_pool: {
    type: 'swimming_pool',
    name: 'Hồ bơi vô cực VIP',
    baseHourlyRateVND: 50000,
    maxHoursPerSlot: 2,
    peakHourMultiplier: 1.1,
  },
  community_hall: {
    type: 'community_hall',
    name: 'Phòng sinh hoạt cộng đồng',
    baseHourlyRateVND: 150000,
    maxHoursPerSlot: 6,
    peakHourMultiplier: 1.3,
  },
};

export interface BookingFeeOptions {
  facilityType: FacilityType;
  hours: number;
  isPeakHour?: boolean;
  isVipMember?: boolean;
}

export function calculateFacilityBookingFee(options: BookingFeeOptions): number {
  const { facilityType, hours, isPeakHour = false, isVipMember = false } = options;
  const rate = FACILITY_RATES[facilityType];

  if (!rate) {
    throw new Error(`Invalid facility type: ${facilityType}`);
  }

  if (hours <= 0) {
    return 0;
  }

  // Giới hạn số giờ tối đa cho mỗi lượt đặt
  const effectiveHours = Math.min(hours, rate.maxHoursPerSlot);

  // Áp dụng hệ số giờ cao điểm nếu có
  const multiplier = isPeakHour ? rate.peakHourMultiplier : 1.0;
  const subtotal = Math.ceil(effectiveHours) * rate.baseHourlyRateVND * multiplier;

  // Thành viên VIP được giảm 15% tổng hóa đơn
  const discount = isVipMember ? subtotal * 0.15 : 0;

  return Math.round(subtotal - discount);
}
