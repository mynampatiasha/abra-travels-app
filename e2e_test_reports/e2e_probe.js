// READ-ONLY probe of the E2E footprint in the abra_fleet database. Prints counts/statuses only.
require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI, { serverSelectionTimeoutMS: 20000 }); await c.connect();
  const db = c.db(); const E = { $regex: '^e2e\.', $options: 'i' };
  const group = async (col, filter, field) => { const r = await db.collection(col).aggregate([{ $match: filter }, { $group: { _id: '$' + field, n: { $sum: 1 } } }]).toArray(); return Object.fromEntries(r.map((x) => [String(x._id), x.n])); };
  console.log('probe time:', new Date().toISOString());
  for (const col of ['customers', 'users']) console.log(`${col} (e2e):`, await db.collection(col).countDocuments({ email: E }));
  console.log('rosters (e2e) by status:', await group('rosters', { customerEmail: E }, 'status'));
  console.log('rosters (e2e) by type  :', await group('rosters', { customerEmail: E }, 'rosterType'));
  console.log('notifications (e2e recipients):', await db.collection('notifications').countDocuments({ userEmail: E }));
  console.log('drivers named E2E:', await db.collection('drivers').countDocuments({ $or: [{ email: E }, { 'personalInfo.email': E }] }), '| vehicles E2E:', await db.collection('vehicles').countDocuments({ registrationNumber: { $regex: '^E2E', $options: 'i' } }));
  console.log('real data untouched check -> rosters total:', await db.collection('rosters').countDocuments({}), '(was 73 at migration) | pending_assignment non-e2e:', await db.collection('rosters').countDocuments({ status: 'pending_assignment', customerEmail: { $not: E } }));
  await c.close();
})().catch((e) => { console.error('ERR', String(e.message).replace(/\/\/[^@]*@/g, '//***:***@')); process.exit(1); });
