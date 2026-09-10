import http from 'node:http';
import { getConfig } from './config.js';
import { AppCheckService } from './modules/auth/appCheck.js';
import { calculateParkingFee, PARKING_RATES } from './modules/parking/rates.js';
import { calculateMaintenanceFee } from './modules/fee/calculation.js';
import { ResidentFilterManager } from './modules/admin/filter.js';
import { calculateFacilityBookingFee, FACILITY_RATES } from './modules/facility/booking.js';

const config = getConfig();
const appCheck = new AppCheckService(config.enforceAppCheck);
const filterManager = new ResidentFilterManager();

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const appCheckToken = req.headers['x-firebase-appcheck'] as string | undefined;

  // Verify App Check
  const appCheckStatus = appCheck.verifyToken(appCheckToken);
  if (!appCheckStatus.valid && config.enforceAppCheck) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Unauthorized: Firebase App Check failed', details: appCheckStatus }));
    return;
  }

  res.setHeader('Content-Type', 'application/json');

  if (url.pathname === '/health' || url.pathname === '/') {
    res.writeHead(200);
    res.end(
      JSON.stringify({
        status: 'UP',
        service: 'PiCare API',
        environment: config.env,
        firebaseProject: config.firebaseProject,
        version: config.version,
        timestamp: new Date().toISOString(),
      })
    );
    return;
  }

  if (url.pathname === '/api/parking/rates') {
    res.writeHead(200);
    res.end(JSON.stringify(PARKING_RATES));
    return;
  }

  if (url.pathname === '/api/parking/calculate') {
    const type = (url.searchParams.get('type') || 'car_standard') as any;
    const hours = parseFloat(url.searchParams.get('hours') || '2');
    try {
      const fee = calculateParkingFee(type, hours);
      res.writeHead(200);
      res.end(JSON.stringify({ type, hours, feeVND: fee }));
    } catch (err: any) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: err.message || 'Bad Request' }));
    }
    return;
  }

  if (url.pathname === '/api/fee/maintenance') {
    const area = parseFloat(url.searchParams.get('area') || '75');
    const rate = parseFloat(url.searchParams.get('rate') || '15000');
    const phase = (parseInt(url.searchParams.get('phase') || '2', 10) as 1 | 2);
    const fee = calculateMaintenanceFee({ apartmentAreaM2: area, ratePerM2VND: rate, phase });
    res.writeHead(200);
    res.end(JSON.stringify({ apartmentAreaM2: area, phase, feeVND: fee }));
    return;
  }

  if (url.pathname === '/api/facility/rates') {
    res.writeHead(200);
    res.end(JSON.stringify(FACILITY_RATES));
    return;
  }

  if (url.pathname === '/api/facility/calculate') {
    const facilityType = (url.searchParams.get('type') || 'bbq_area') as any;
    const hours = parseFloat(url.searchParams.get('hours') || '2');
    const isPeakHour = url.searchParams.get('peak') === 'true';
    const isVipMember = url.searchParams.get('vip') === 'true';
    const fee = calculateFacilityBookingFee({ facilityType, hours, isPeakHour, isVipMember });
    res.writeHead(200);
    res.end(JSON.stringify({ facilityType, hours, isPeakHour, isVipMember, feeVND: fee }));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

if (process.env.NODE_ENV !== 'test') {
  server.listen(config.port, () => {
    console.log(`[PiCare] Running in ${config.env} on port ${config.port} (Firebase: ${config.firebaseProject})`);
  });
}

export { server, appCheck, filterManager, calculateFacilityBookingFee, FACILITY_RATES };
