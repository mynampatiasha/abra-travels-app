// Creates the E2E rosters through the REAL customer API (POST /api/roster/customer/bulk), logged in as each test customer.
// Run only after the admin has approved the E2E customers. Prints HTTP status + ids; never prints passwords/tokens.
const acc = require('./e2e_accounts.json').customers;
const API = 'http://localhost:3001';
const OFFICE = 'Electronic City Office, Bangalore';
const WEEK = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
const geo = (lat, lng, address) => ({ latitude: lat, longitude: lng, address });
const PLACES = {
  anita: geo(12.9352, 77.6245, 'Koramangala 5th Block, Bangalore'),
  ravi: geo(12.9784, 77.6408, 'Indiranagar, Bangalore'),
  meera: geo(12.9116, 77.6474, 'HSR Layout, Bangalore'),
  karthik: geo(12.9698, 77.7500, 'Whitefield, Bangalore'),
  zoya: geo(12.9299, 77.5838, 'Jayanagar, Bangalore'),
};
const ofc = geo(12.8452, 77.6602, OFFICE);
const base = (key, extra) => ({
  officeLocation: OFFICE, officeLocationCoordinates: ofc, weekdays: WEEK,
  loginPickupAddress: PLACES[key].address, loginPickupLocation: PLACES[key],
  logoutDropAddress: PLACES[key].address, logoutDropLocation: PLACES[key],
  notes: 'E2E test roster', ...extra,
});
// 2026-11-02 is a Monday
const PLAN = {
  'e2e.anita@e2etest.com': base('anita', { rosterType: 'both', fromDate: '2026-11-02', toDate: '2026-11-06', fromTime: '09:00', toTime: '18:00' }),
  'e2e.ravi@e2etest.com': base('ravi', { rosterType: 'login', weekdays: ['Monday'], fromDate: '2026-11-02', toDate: '2026-11-02', fromTime: '09:00', toTime: '18:00' }),
  'e2e.meera@e2etest.com': base('meera', { rosterType: 'both', fromDate: '2026-11-02', toDate: '2026-11-06', fromTime: '09:00', toTime: '18:00' }),
  'e2e.karthik@e2etest.com': base('karthik', { rosterType: 'logout', fromDate: '2026-11-02', toDate: '2026-11-06', fromTime: '09:00', toTime: '18:30' }),
  'e2e.zoya@e2eother.com': base('zoya', { rosterType: 'both', fromDate: '2026-11-02', toDate: '2026-11-06', fromTime: '09:00', toTime: '18:00' }),
};
(async () => {
  for (const a of acc) {
    const l = await fetch(API + '/api/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: a.email, password: a.password }) });
    const lj = await l.json().catch(() => ({}));
    lj.token = lj.token || (lj.data && lj.data.token);
    if (!lj.token) { console.log(`${a.email}: login HTTP ${l.status} (${lj.message || lj.error}) - roster NOT created`); continue; }
    const item = { customerName: a.name, customerEmail: a.email, phoneNumber: a.phone, companyName: 'E2E Test Company', ...PLAN[a.email] };
    const r = await fetch(API + '/api/roster/customer', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + lj.token }, body: JSON.stringify(item) });
    const j = await r.json().catch(() => ({}));
    console.log(`${a.email}: roster POST HTTP ${r.status} ${j.success === false ? 'FAIL ' + (j.message || JSON.stringify(j.errors || j.error || '').slice(0, 200)) : 'ok ' + JSON.stringify(j.data ? (j.data.created || j.data.rosterIds || j.data).length ?? '' : '')}`);
  }
})().catch((e) => console.error('ERR', e.message));
