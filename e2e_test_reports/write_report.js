require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const fs = require('fs');
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect(); const db = c.db(); const E = { $regex: '^e2e\.', $options: 'i' };
  const cust = await db.collection('customers').find({ email: E }, { projection: { email: 1 } }).toArray();
  const ros = await db.collection('rosters').find({ customerEmail: E }, { projection: { customerEmail: 1, rosterType: 1 } }).toArray();
  await c.close();
  const md = `# Part A - End-to-end roster flow - test report (2026-10-31)

Environment: local backend http://localhost:3001 -> Atlas FleetCluster / database \`abra_fleet\`. Web app: for web builds main.dart ignores abra_fleet/.env and uses API_BASE_URL=http://localhost:3001 (confirmed in code and by a login recorded in the new DB).
Test data: customers e2e.*@e2etest.com (company e2etest) + e2e.zoya@e2eother.com (company e2eother). Credentials in e2e_accounts.json (untracked - never commit).
Method (to save time/credits): accounts and rosters are created by scripts that call the SAME real APIs the app uses (/api/auth/register, /api/auth/login, /api/roster/customer); the browser is used for admin screens.

| ID | Step | Expected | Actual | Result | Evidence |
|----|------|----------|--------|--------|----------|
| A0 | Which backend does the UI call | localhost:3001 | main.dart (web) hardcodes localhost:3001; login by test customer recorded in new DB | PASS | code + DB lastLogin |
| A1 | Customer registration (UI, E2E Anita) | pending account created | customers doc status=pending, isActive=false; POST /api/auth/register seen in network log | PASS | UI + DB |
| A1b | Registration via API for 4 more; client-supplied status:'active' | must NOT bypass approval | all 5 stayed inactive; login = HTTP 403 "inactive" until admin approved | PASS | API |
| A1c | Admin approval, then customers can log in | login 200 | all 5 logged in (HTTP 200) after approval | PASS | API + DB (status=active) |
| A1d | Create roster as customer via /api/roster/customer/bulk | roster created | HTTP 400 "Admin organization not found" for ALL 5 customers | FAIL (BUG-1) | API |
| A1e | Create roster via /api/roster/customer (single) | 201 | 4 of 5 created; Ravi's one-day roster refused "End date must be after start date" | PARTIAL (BUG-2) | API |
| A1f | Ravi's roster with a 2-day range | 201 | created | PASS | API + DB |
| A2 | Admin Pending Rosters screen | all E2E rosters once, correct counts | 5 shown; Total 5, Login 1, Logout 1, Both 3 = DB; E2E badge/company shown; dashboard counter moved 72 -> 73 live | PASS | screenshot + DB |
| A2b | Search/filter/sort/export, edit & delete (soft-cancel), date-range filter | work | not exercised yet. Note: 5 REAL rosters were soft-cancelled by admin@abrafleet.com at 12:03-12:05 IST (before this run) - proves delete works (A9) | TODO | DB |
| A3a/b | Manual Assign / Auto route optimisation | assigned, leave Pending | BLOCKED - no E2E drivers/vehicles yet (Part B) | BLOCKED | probe: 0 drivers, 0 vehicles |
| A4-A9 | Conflicts, notifications matrix, driver app, customer view, leave, regression | | depends on A3 | TODO | |

## Bugs / findings
- BUG-1 (Major) POST /api/roster/customer/bulk uses users.findOne({firebaseUid: JWT userId}) (routes/roster_router.js ~line 249). After Firebase removal the JWT userId is the Mongo _id, so the lookup is empty and every customer gets 400 "Admin organization not found". The customer app also calls this endpoint (roster_repository.dart:236).
- BUG-2 (Minor/Design) A one-day roster (fromDate == toDate) is rejected: "End date must be after start date".
- BUG-3 (Major data/UX) Dashboard "Pending Rosters" = 73 (counts status=pending_assignment) but the Pending Rosters screen shows 5. All 68 real "pending" rosters already carry a vehicle/driver/trip id and have end dates in the past, so the screen hides them; the dashboard number is misleading.
- OBS-4 Dashboard "Total Drivers" shows 0 although 3 real drivers exist ("Active & Available" may exclude them; check status values).
- OBS-5 Dashboard "Total Customers" 95 while the customers collection holds 100 after adding 5 E2E accounts (check what is counted).
- OBS-6 Registration form: Branch/Location is free text; Department list comes from DB; the form also allows self-registration as Driver (relevant to Part B).
- OBS-7 5 real rosters were cancelled by admin@abrafleet.com during this session (not by the test). Confirm intentional; reversible (soft-cancel).
- Security note: client-supplied status on /api/auth/register is ignored/overridden (good).

## E2E records created (collection / _id) - for cleanup
customers: ${cust.map((x) => x._id + ' (' + x.email + ')').join(', ')}
rosters: ${ros.map((x) => x._id + ' (' + x.customerEmail + ', ' + x.rosterType + ')').join(', ')}
`;
  fs.writeFileSync('PARTA_REPORT_2026-10-31.md', md); console.log('report written');
})();
