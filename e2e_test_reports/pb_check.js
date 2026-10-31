require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect(); const db = c.db();
  const dr = await db.collection('drivers').find({ $or: [{ 'personalInfo.email': { $regex: 'e2e', $options: 'i' } }, { email: { $regex: 'e2e', $options: 'i' } }, { 'personalInfo.firstName': { $regex: 'e2e', $options: 'i' } }] }, { projection: { driverId: 1, status: 1, loginStatus: 1, assignedVehicle: 1, assignedVehicleId: 1, vehicleId: 1 } }).toArray();
  const ve = await db.collection('vehicles').find({ registrationNumber: { $regex: 'e2e', $options: 'i' } }, { projection: { registrationNumber: 1, status: 1, capacity: 1, seatCapacity: 1, assignedDriver: 1, assignedDriverId: 1, driverId: 1 } }).toArray();
  console.log('E2E drivers:', JSON.stringify(dr.map((d) => ({ id: d.driverId, status: d.status, login: d.loginStatus, hasVehicle: !!(d.assignedVehicle || d.assignedVehicleId || d.vehicleId) }))));
  console.log('E2E vehicles:', JSON.stringify(ve.map((v) => ({ reg: v.registrationNumber, status: v.status, cap: v.capacity || v.seatCapacity, hasDriver: !!(v.assignedDriver || v.assignedDriverId || v.driverId) }))));
  await c.close();
})();
