/**
 * Parking Module: Biểu phí ô tô PiCare
 * PR #3916 - feat(parking): biểu phí ô tô (Issue #3952)
 */

export type VehicleType = 'motorbike' | 'car_standard' | 'car_suv';

export interface ParkingRate {
  vehicleType: VehicleType;
  baseHourlyRateVND: number;
  dailyCapVND: number;
  monthlySubscriptionVND: number;
}

export const PARKING_RATES: Record<VehicleType, ParkingRate> = {
  motorbike: {
    vehicleType: 'motorbike',
    baseHourlyRateVND: 5000,
    dailyCapVND: 30000,
    monthlySubscriptionVND: 120000,
  },
  car_standard: {
    vehicleType: 'car_standard',
    baseHourlyRateVND: 25000,
    dailyCapVND: 150000,
    monthlySubscriptionVND: 1200000,
  },
  car_suv: {
    vehicleType: 'car_suv',
    baseHourlyRateVND: 35000,
    dailyCapVND: 200000,
    monthlySubscriptionVND: 1500000,
  },
};

export function calculateParkingFee(
  vehicleType: VehicleType,
  hours: number,
  hasMonthlyPass = false
): number {
  if (hasMonthlyPass) return 0;
  if (isNaN(hours) || hours <= 0) return 0;

  const rate = PARKING_RATES[vehicleType];
  if (!rate) {
    throw new Error(
      `Invalid vehicle type: '${vehicleType}'. Supported types: ${Object.keys(PARKING_RATES).join(', ')}`
    );
  }

  const calculated = Math.ceil(hours) * rate.baseHourlyRateVND;
  const days = Math.floor(hours / 24);
  const remainingHours = hours % 24;

  if (hours <= 24) {
    return Math.min(calculated, rate.dailyCapVND);
  }

  return (
    days * rate.dailyCapVND +
    Math.min(Math.ceil(remainingHours) * rate.baseHourlyRateVND, rate.dailyCapVND)
  );
}
