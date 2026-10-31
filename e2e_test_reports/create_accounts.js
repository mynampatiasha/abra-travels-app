// Creates the remaining E2E customer logins through the REAL registration API (same endpoint the UI uses), then checks each can log in.
require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
const acc = require('./e2e_accounts.json').customers;
const API = 'http://localhost:3001';
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect();
  const anita = await c.db().collection('customers').findOne({ email: acc[0].email });
  const skip = new Set(['_id', 'password', 'passwordHash', 'createdAt', 'updatedAt', 'name', 'email', 'phone', 'status', 'isActive', 'role', 'customerId', 'userId', 'firebaseUid']);
  const shared = Object.fromEntries(Object.entries(anita).filter(([k]) => !skip.has(k)));
  console.log('profile fields the UI stored (names):', Object.keys(shared).join(', '));
  await c.close();
  for (const a of acc.slice(1)) {
    const body = { ...shared, name: a.name, email: a.email, phone: a.phone, password: a.password, role: 'customer', status: 'active' };
    const r = await fetch(API + '/api/auth/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    console.log(`register ${a.email}: HTTP ${r.status} ${j.success === false ? 'FAIL ' + (j.message || j.error) : 'ok'}`);
  }
  for (const a of acc) {
    const r = await fetch(API + '/api/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: a.email, password: a.password }) });
    const j = await r.json().catch(() => ({}));
    console.log(`login    ${a.email}: HTTP ${r.status} ${j.token ? 'TOKEN ISSUED' : (j.message || j.error || '')}`);
  }
})().catch((e) => console.error('ERR', String(e.message).replace(/\/\/[^@]*@/g, '//***:***@')));
