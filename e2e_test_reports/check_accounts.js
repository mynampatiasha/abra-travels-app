require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect(); const db = c.db(); const E = { $regex: '^e2e\.', $options: 'i' };
  for (const col of ['customers', 'users', 'employee_admins', 'admin_users']) {
    const d = await db.collection(col).find({ email: E }, { projection: { email: 1, status: 1, role: 1, isActive: 1, approvalStatus: 1 } }).toArray();
    if (d.length) console.log(col + ':', JSON.stringify(d.map((x) => ({ email: x.email, status: x.status, role: x.role, approval: x.approvalStatus, active: x.isActive }))));
  }
  await c.close();
})().catch((e) => console.error('ERR', String(e.message).replace(/\/\/[^@]*@/g, '//***:***@')));
