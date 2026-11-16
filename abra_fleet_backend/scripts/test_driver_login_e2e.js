// scripts/test_driver_login_e2e.js
// ============================================================================
// Automated API test for the driver login-credentials feature (B4).
// Exercises the running local backend (http://localhost:3001) over HTTP only
// — it never writes to MongoDB directly. All records it creates are named
// "E2E ..." / "e2e.*@e2e.test" so they are safe to identify and clean up.
//
// Uses the backend's NODE_ENV=development test-auth header bypass
// (x-test-user-id / x-test-role) to act as an admin for the admin-only
// routes; driver-facing routes are exercised with real email+password logins.
// ============================================================================

require('dotenv').config();
const { MongoClient } = require('mongodb');

const BASE = process.env.TEST_BASE_URL || 'http://localhost:3001';
const RUN_ID = Date.now();

const results = [];
function record(name, pass, info) {
  results.push({ name, pass, info: info || '' });
  console.log(`${pass ? '✅ PASS' : '❌ FAIL'} - ${name}${info ? ' :: ' + info : ''}`);
}

const adminHeaders = {
  'Content-Type': 'application/json',
  'x-test-user-id': '000000000000000000000000',
  'x-test-role': 'admin',
};

async function api(method, path, { body, token, headers } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(headers || {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* no body */ }
  return { status: res.status, json };
}

const SUFFIX_DIGIT = { a: '1', b: '2', c: '3' };

async function createDriver(suffix, { withEmail = true, firstName } = {}) {
  // Driver creation requires a truthy email, so "no valid email" is
  // simulated with a non-empty string that isn't a real email address —
  // the create-login endpoint's own email-format check should catch this.
  const email = withEmail ? `e2e.driver.${suffix}.${RUN_ID}@e2e.test` : 'not-an-email';
  const phone = `9${String(RUN_ID).slice(-8)}${SUFFIX_DIGIT[suffix] || '9'}`;
  const body = {
    personalInfo: {
      firstName: firstName || `E2E`,
      lastName: `Driver ${suffix.toUpperCase()}`,
      email,
      phone,
    },
    license: { licenseNumber: `E2E-LIC-${suffix}-${RUN_ID}`, type: 'LMV' },
  };
  const { status, json } = await api('POST', '/api/admin/drivers', { body, headers: adminHeaders });
  return { status, json, email, phone };
}

async function run() {
  const createdDrivers = []; // { label, driverId, _id, email }

  console.log(`\n=== Driver login credentials E2E test run ${RUN_ID} ===`);
  console.log(`Base URL: ${BASE}\n`);

  // ---- B1-style setup: create two E2E drivers ---------------------------
  const a = await createDriver('a');
  record('Create E2E Driver A', a.status === 201 && a.json?.success, `status=${a.status}`);
  if (a.json?.data) createdDrivers.push({ label: 'E2E Driver A', driverId: a.json.data.driverId, _id: a.json.data._id, email: a.email });

  const b = await createDriver('b');
  record('Create E2E Driver B', b.status === 201 && b.json?.success, `status=${b.status}`);
  if (b.json?.data) createdDrivers.push({ label: 'E2E Driver B', driverId: b.json.data.driverId, _id: b.json.data._id, email: b.email });

  // Duplicate email/phone rejected at creation
  const dup = await createDriver('a'); // same email/phone as Driver A
  record('Duplicate email/phone rejected at driver creation', dup.status === 400 && !dup.json?.success, `status=${dup.status} msg=${dup.json?.message}`);

  // Missing required field rejected
  const missing = await api('POST', '/api/admin/drivers', {
    body: { personalInfo: { firstName: 'E2E', lastName: 'NoPhone' } },
    headers: adminHeaders,
  });
  record('Missing required field rejected at driver creation', missing.status === 400, `status=${missing.status}`);

  // Driver without a valid email cannot get a login
  const c = await createDriver('c', { withEmail: false });
  record('Create E2E Driver C (no email)', c.status === 201, `status=${c.status}`);
  if (c.json?.data) createdDrivers.push({ label: 'E2E Driver C (no email)', driverId: c.json.data.driverId, _id: c.json.data._id, email: null });
  if (c.json?.data) {
    const noEmailLogin = await api('POST', `/api/admin/drivers/${c.json.data.driverId}/login`, { headers: adminHeaders });
    record('Create login refused for driver with no email', noEmailLogin.status === 400 && !noEmailLogin.json?.success, `status=${noEmailLogin.status} msg=${noEmailLogin.json?.message}`);
  }

  if (!a.json?.data || !b.json?.data) {
    console.log('\n❌ Cannot continue - Driver A or B was not created.');
    return finish(createdDrivers);
  }
  const driverA = a.json.data;
  const driverB = b.json.data;

  // ---- Driver A: create login -> login -> forced change -------------------
  const createLoginA = await api('POST', `/api/admin/drivers/${driverA.driverId}/login`, { headers: adminHeaders });
  record('Create login for Driver A', createLoginA.status === 200 && createLoginA.json?.success, `status=${createLoginA.status}`);
  const tempPassA1 = createLoginA.json?.data?.temporaryPassword;
  const usernameA = createLoginA.json?.data?.username;

  const createLoginAgainA = await api('POST', `/api/admin/drivers/${driverA.driverId}/login`, { headers: adminHeaders });
  record('Second "create login" on Driver A is refused', createLoginAgainA.status === 400 && !createLoginAgainA.json?.success, `status=${createLoginAgainA.status}`);

  const loginA1 = await api('POST', '/api/auth/login', { body: { email: usernameA, password: tempPassA1 } });
  record('Driver A logs in with temporary password', loginA1.status === 200 && loginA1.json?.success, `status=${loginA1.status}`);
  record('Login response flags mustChangePassword for Driver A', loginA1.json?.data?.user?.mustChangePassword === true, '');
  const tokenA1 = loginA1.json?.data?.token;

  const meA1 = await api('GET', '/api/auth/me', { token: tokenA1 });
  record('/api/auth/me reflects mustChangePassword for Driver A', meA1.json?.data?.user?.mustChangePassword === true, '');

  const changePassA = await api('POST', '/api/auth/change-password', {
    token: tokenA1,
    body: { currentPassword: tempPassA1, newPassword: 'E2eNewPass!2345' },
  });
  record('Driver A changes password', changePassA.status === 200 && changePassA.json?.success, `status=${changePassA.status}`);

  const loginOldPassA = await api('POST', '/api/auth/login', { body: { email: usernameA, password: tempPassA1 } });
  record('Old temporary password no longer works for Driver A', loginOldPassA.status === 401 && !loginOldPassA.json?.success, `status=${loginOldPassA.status}`);

  const loginNewPassA = await api('POST', '/api/auth/login', { body: { email: usernameA, password: 'E2eNewPass!2345' } });
  record('New password works for Driver A', loginNewPassA.status === 200 && loginNewPassA.json?.success, `status=${loginNewPassA.status}`);
  record('mustChangePassword cleared for Driver A after change', loginNewPassA.json?.data?.user?.mustChangePassword === false, '');

  // ---- Driver B: create login -> reset -> token invalidation -> disable/enable
  const createLoginB = await api('POST', `/api/admin/drivers/${driverB.driverId}/login`, { headers: adminHeaders });
  record('Create login for Driver B', createLoginB.status === 200 && createLoginB.json?.success, `status=${createLoginB.status}`);
  const tempPassB1 = createLoginB.json?.data?.temporaryPassword;
  const usernameB = createLoginB.json?.data?.username;

  const loginB1 = await api('POST', '/api/auth/login', { body: { email: usernameB, password: tempPassB1 } });
  record('Driver B logs in with first temporary password', loginB1.status === 200 && loginB1.json?.success, `status=${loginB1.status}`);
  const tokenB1 = loginB1.json?.data?.token;

  const resetB = await api('POST', `/api/admin/drivers/${driverB.driverId}/login/reset`, { headers: adminHeaders });
  record('Reset password for Driver B', resetB.status === 200 && resetB.json?.success, `status=${resetB.status}`);
  const tempPassB2 = resetB.json?.data?.temporaryPassword;

  const meB1AfterReset = await api('GET', '/api/auth/me', { token: tokenB1 });
  record('Driver B old token invalidated immediately after reset', meB1AfterReset.status === 401, `status=${meB1AfterReset.status} code=${meB1AfterReset.json?.code}`);

  const loginOldPassB = await api('POST', '/api/auth/login', { body: { email: usernameB, password: tempPassB1 } });
  record('Old temporary password no longer works for Driver B after reset', loginOldPassB.status === 401, `status=${loginOldPassB.status}`);

  const loginB2 = await api('POST', '/api/auth/login', { body: { email: usernameB, password: tempPassB2 } });
  record('Driver B logs in with reset temporary password', loginB2.status === 200 && loginB2.json?.success, `status=${loginB2.status}`);
  const tokenB2 = loginB2.json?.data?.token;

  const disableB = await api('POST', `/api/admin/drivers/${driverB.driverId}/login/disable`, { headers: adminHeaders });
  record('Disable login for Driver B', disableB.status === 200 && disableB.json?.success, `status=${disableB.status}`);

  const meB2AfterDisable = await api('GET', '/api/auth/me', { token: tokenB2 });
  record('Driver B existing session stops working after disable', meB2AfterDisable.status !== 200, `status=${meB2AfterDisable.status} code=${meB2AfterDisable.json?.code}`);

  const loginWhileDisabledB = await api('POST', '/api/auth/login', { body: { email: usernameB, password: tempPassB2 } });
  record('Login refused while Driver B is disabled', loginWhileDisabledB.status === 403, `status=${loginWhileDisabledB.status}`);

  const enableB = await api('POST', `/api/admin/drivers/${driverB.driverId}/login/enable`, { headers: adminHeaders });
  record('Enable login for Driver B', enableB.status === 200 && enableB.json?.success, `status=${enableB.status}`);

  const loginAfterEnableB = await api('POST', '/api/auth/login', { body: { email: usernameB, password: tempPassB2 } });
  record('Driver B can log in again after enable', loginAfterEnableB.status === 200 && loginAfterEnableB.json?.success, `status=${loginAfterEnableB.status}`);

  // ---- Read-only DB verification (counts/booleans only, no secrets) -------
  await verifyInDb(driverA.driverId, driverB.driverId);

  console.log(`\nDriver B is left ACTIVE with mustChangePassword=true and a known temporary password, for use in the browser forced-change-password test (B4).`);

  finish(createdDrivers);
}

async function verifyInDb(driverIdA, driverIdB) {
  let client;
  try {
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    const db = client.db();
    const drivers = db.collection('drivers');

    const docA = await drivers.findOne({ driverId: driverIdA }, { projection: { loginStatus: 1, mustChangePassword: 1, tokenVersion: 1 } });
    const docB = await drivers.findOne({ driverId: driverIdB }, { projection: { loginStatus: 1, mustChangePassword: 1, tokenVersion: 1 } });

    record('DB: Driver A loginStatus=ACTIVE, mustChangePassword=false', docA?.loginStatus === 'ACTIVE' && docA?.mustChangePassword === false, JSON.stringify({ loginStatus: docA?.loginStatus, mustChangePassword: docA?.mustChangePassword }));
    record('DB: Driver B loginStatus=ACTIVE, tokenVersion>=2 (reset+disable bumped it)', docB?.loginStatus === 'ACTIVE' && (docB?.tokenVersion || 0) >= 2, JSON.stringify({ loginStatus: docB?.loginStatus, tokenVersion: docB?.tokenVersion }));

    const auditCount = await db.collection('audit_logs').countDocuments({ driverId: { $in: [driverIdA, driverIdB] } });
    record('Audit log entries recorded for these actions', auditCount >= 4, `count=${auditCount}`);
  } catch (err) {
    record('Read-only DB verification', false, err.message);
  } finally {
    if (client) await client.close();
  }
}

function finish(createdDrivers) {
  const total = results.length;
  const passed = results.filter(r => r.pass).length;
  console.log(`\n=== Summary: ${passed}/${total} passed ===`);

  console.log('\nE2E records created this run (for cleanup):');
  for (const d of createdDrivers) {
    console.log(`  - drivers / ${d._id}  (driverId=${d.driverId}, ${d.label}${d.email ? ', email=' + d.email : ''})`);
  }
  console.log('  - audit_logs / entries with driverId in the above (see audit_logs collection)');

  if (passed !== total) process.exitCode = 1;
}

run().catch((err) => {
  console.error('FATAL TEST ERROR:', err);
  process.exitCode = 1;
});
