require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect(); const db = c.db(); const E = { $regex: '^e2e\.', $options: 'i' };
  const real = { customerEmail: { $not: E } };
  console.log('real rosters by status:', JSON.stringify(Object.fromEntries((await db.collection('rosters').aggregate([{ $match: real }, { $group: { _id: '$status', n: { $sum: 1 } } }]).toArray()).map((x) => [x._id, x.n]))));
  const changed = await db.collection('rosters').find({ ...real, status: { $ne: 'pending_assignment' } }, { projection: { status: 1, updatedAt: 1, createdAt: 1, assignedAt: 1, vehicleId: 1, driverId: 1, tripId: 1, cancelledAt: 1, cancelledBy: 1, assignedBy: 1 } }).toArray();
  for (const r of changed) console.log(JSON.stringify({ id: String(r._id).slice(-6), status: r.status, updatedAt: r.updatedAt, assignedAt: r.assignedAt, cancelledAt: r.cancelledAt, hasVehicle: !!r.vehicleId, hasDriver: !!r.driverId, hasTrip: !!r.tripId, by: r.assignedBy || r.cancelledBy }));
  await c.close();
})();
