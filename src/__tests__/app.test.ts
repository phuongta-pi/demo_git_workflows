import test from 'node:test';
import assert from 'node:assert';
import { AppCheckService } from '../modules/auth/appCheck.js';
import { calculateParkingFee, PARKING_RATES } from '../modules/parking/rates.js';
import { calculateMaintenanceFee } from '../modules/fee/calculation.js';
import { ResidentFilterManager } from '../modules/admin/filter.js';
import { calculateFacilityBookingFee } from '../modules/facility/booking.js';

test('AppCheckService enforces tokens when enabled', () => {
  const serviceEnforced = new AppCheckService(true);
  assert.strictEqual(serviceEnforced.verifyToken().valid, false);
  assert.strictEqual(serviceEnforced.verifyToken('invalid-token').valid, false);
  assert.strictEqual(serviceEnforced.verifyToken('valid-app-check-token-app123').valid, true);

  const serviceBypass = new AppCheckService(false);
  assert.strictEqual(serviceBypass.verifyToken().valid, true);
});

test('Parking rate calculator handles hourly and daily cap correctly', () => {
  // Motorbike: 5,000 / hour, cap 30,000
  assert.strictEqual(calculateParkingFee('motorbike', 2), 10000);
  assert.strictEqual(calculateParkingFee('motorbike', 10), 30000); // capped

  // Car standard: 25,000 / hour, cap 150,000
  assert.strictEqual(calculateParkingFee('car_standard', 2), 50000);
  assert.strictEqual(calculateParkingFee('car_standard', 8), 150000); // capped

  // Monthly pass: free daily
  assert.strictEqual(calculateParkingFee('car_standard', 10, true), 0);
});

test('Maintenance fee applies phase 2 multiplier correctly', () => {
  const feeP1 = calculateMaintenanceFee({
    apartmentAreaM2: 100,
    ratePerM2VND: 10000,
    phase: 1,
  });
  assert.strictEqual(feeP1, 1000000);

  const feeP2 = calculateMaintenanceFee({
    apartmentAreaM2: 100,
    ratePerM2VND: 10000,
    phase: 2,
  });
  assert.strictEqual(feeP2, 1050000); // 1.05x
});

test('ResidentFilterManager retains existing filter state', () => {
  const manager = new ResidentFilterManager();
  manager.applyFilter({ buildingBlock: 'Tower A' });
  const updated = manager.applyFilter({ floor: 12 });

  assert.strictEqual(updated.buildingBlock, 'Tower A');
  assert.strictEqual(updated.floor, 12);
});

test('Facility booking fee calculates correct base, peak surcharge, and VIP discount', () => {
  // BBQ Area: 100,000 / hour, max 4h
  const bbqFee = calculateFacilityBookingFee({ facilityType: 'bbq_area', hours: 2 });
  assert.strictEqual(bbqFee, 200000);

  // BBQ Area capped at max 4h
  const bbqCapped = calculateFacilityBookingFee({ facilityType: 'bbq_area', hours: 6 });
  assert.strictEqual(bbqCapped, 400000);

  // Tennis Court: 80,000 / h, peak multiplier 1.2x -> 2h = 160,000 * 1.2 = 192,000
  const tennisPeak = calculateFacilityBookingFee({
    facilityType: 'tennis_court',
    hours: 2,
    isPeakHour: true,
  });
  assert.strictEqual(tennisPeak, 192000);

  // Swimming Pool: 50,000 / h -> 2h = 100,000. VIP gets 15% off = 85,000
  const poolVip = calculateFacilityBookingFee({
    facilityType: 'swimming_pool',
    hours: 2,
    isVipMember: true,
  });
  assert.strictEqual(poolVip, 85000);

  // 0 hours = 0 fee
  assert.strictEqual(calculateFacilityBookingFee({ facilityType: 'bbq_area', hours: 0 }), 0);
});
