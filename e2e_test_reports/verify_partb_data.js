require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
const acc = require('./e2e_accounts.json');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect(); const db = c.db();
  const dr = await db.collection('drivers').find({ 'personalInfo.email': { $regex: '^e2e\.driver', $options: 'i' } }).toArray();
  for (const d of dr) console.log('driver', d.driverId, '| status:', d.status, '| loginStatus:', d.loginStatus, '| assignedVehicle:', d.assignedVehicle, '| hasPasswordHash:', !!(d.password && String(d.password).startsWith('$2')), '| mustChangePassword:', d.mustChangePassword);
  const ve = await db.collection('vehicles').find({ registrationNumber: { $in: ['KA01ZZ0001', 'KA01ZZ0002'] } }).toArray();
  for (const v of ve) console.log('vehicle', v.registrationNumber, v.vehicleId, '| status:', v.status, '| seats:', v.seatingCapacity || v.capacity, '| assignedDriver:', typeof v.assignedDriver === 'object' ? JSON.stringify(Object.keys(v.assignedDriver || {})) + ' id=' + (v.assignedDriver && (v.assignedDriver.driverId || v.assignedDriver._id)) : v.assignedDriver, '| driverName:', v.driverName || v.assignedDriverName, '| driverEmail:', v.driverEmail || v.assignedDriverEmail);
  await c.close();
  for (const d of acc.drivers) {
    const r = await fetch('http://localhost:3001/api/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: d.email, password: d.password }) });
    const j = await r.json().catch(() => ({}));
    console.log(`login ${d.email}: HTTP ${r.status} ${j.data && j.data.token ? 'TOKEN ok, role=' + j.data.user.role + ', mustChangePassword=' + j.data.user.mustChangePassword + ', loginStatus=' + j.data.user.loginStatus : (j.message || j.error)}`);
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', String(e.message).replace(/\/\/[^@]*@/g, '//***:***@')); process.exit(1); });
