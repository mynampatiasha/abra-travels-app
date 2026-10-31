// Generates TEST-ONLY accounts for the E2E run. Passwords are random and written to e2e_accounts.json (untracked). Never commit that file.
const crypto = require('crypto'), fs = require('fs'), path = require('path');
const out = path.join(__dirname, 'e2e_accounts.json');
if (fs.existsSync(out)) { console.log('e2e_accounts.json already exists - keeping it'); process.exit(0); }
const pw = () => { const a = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'; let s = ''; for (let i = 0; i < 12; i++) s += a[crypto.randomInt(a.length)]; return s + 'a1!'; };
const customers = [
  ['E2E Anita',   'e2e.anita@e2etest.com',   '+919000000001', 'Koramangala 5th Block, Bangalore'],
  ['E2E Ravi',    'e2e.ravi@e2etest.com',    '+919000000002', 'Indiranagar, Bangalore'],
  ['E2E Meera',   'e2e.meera@e2etest.com',   '+919000000003', 'HSR Layout, Bangalore'],
  ['E2E Karthik', 'e2e.karthik@e2etest.com', '+919000000004', 'Whitefield, Bangalore'],
  ['E2E Zoya (other company)', 'e2e.zoya@e2eother.com', '+919000000005', 'Jayanagar, Bangalore'],
].map(([name, email, phone, address]) => ({ role: 'customer', name, email, phone, address, password: pw() }));
fs.writeFileSync(out, JSON.stringify({ createdAt: new Date().toISOString(), note: 'TEST accounts only. Company = first label of the email domain (e2etest / e2eother) - used by the vehicle-compatibility rule.', customers }, null, 2));
console.log(`wrote ${customers.length} test accounts to e2e_accounts.json (passwords not printed)`);
