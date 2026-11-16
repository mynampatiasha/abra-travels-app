require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect(); const db = c.db(); const E = { $regex: '^e2e\.', $options: 'i' };
  const pend = await db.collection('rosters').find({ status: 'pending_assignment', customerEmail: { $not: E } }, { projection: { customerEmail: 1, employeeDetails: 1, vehicleId: 1, driverId: 1, assignedVehicleId: 1, assignedDriverId: 1, tripId: 1, endDate: 1, createdAt: 1, rosterType: 1 } }).toArray();
  const admins = new Set((await db.collection('admin_users').find({}, { projection: { email: 1 } }).toArray()).concat(await db.collection('employee_admins').find({}, { projection: { email: 1 } }).toArray()).map((a) => (a.email || '').toLowerCase()));
  const em = (r) => (r.customerEmail || r.employeeDetails?.email || '').toLowerCase();
  const withAdminEmail = pend.filter((r) => admins.has(em(r))).length;
  const noEmail = pend.filter((r) => !em(r)).length;
  const withTrip = pend.filter((r) => r.tripId || r.vehicleId || r.driverId || r.assignedVehicleId || r.assignedDriverId).length;
  const uniq = new Set(pend.map((r) => em(r) + '|' + (r.rosterType || ''))).size;
  const past = pend.filter((r) => r.endDate && new Date(r.endDate) < new Date('2026-10-31')).length;
  console.log(JSON.stringify({ realPending: pend.length, emailBelongsToAnAdminAccount: withAdminEmail, noEmail, hasVehicleDriverOrTripSet: withTrip, uniqueEmailTypeCombos: uniq, endDateInThePast: past }));
  await c.close();
})();
