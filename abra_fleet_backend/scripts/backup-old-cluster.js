#!/usr/bin/env node
/**
 * READ-ONLY full backup of every database on the cluster in abra_fleet_backend/.env (MONGODB_URI).
 *
 *   node scripts/backup-old-cluster.js <output-dir> [--skip=sample_mflix,admin,local,config]
 *
 * For every collection it writes:
 *   <out>/<db>/<collection>.ejsonl        one canonical Extended-JSON document per line (types preserved)
 *   <out>/<db>/<collection>.indexes.json  index definitions
 * plus <out>/MANIFEST.json (document counts + SHA-256 of each file).
 *
 * It only calls listDatabases / listCollections / find / listIndexes / countDocuments: it can NOT modify the source.
 * Credentials are never printed.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { MongoClient } = require('mongodb');
const { EJSON } = require('bson');

const out = process.argv[2];
if (!out) { console.error('usage: node scripts/backup-old-cluster.js <output-dir> [--skip=db1,db2]'); process.exit(2); }
const skipArg = (process.argv.find((a) => a.startsWith('--skip=')) || '--skip=admin,local,config').split('=')[1];
const SKIP = new Set(skipArg.split(',').map((s) => s.trim()).filter(Boolean));
const mask = (s) => String(s).replace(/\/\/[^@/]*@/g, '//***:***@');

const safe = (n) => n.replace(/[<>:"/\\|?*]/g, '_');
const sha256 = (file) => new Promise((res, rej) => {
  const h = crypto.createHash('sha256');
  fs.createReadStream(file).on('data', (d) => h.update(d)).on('end', () => res(h.digest('hex'))).on('error', rej);
});

(async () => {
  if (!process.env.MONGODB_URI) throw new Error('MONGODB_URI is not set in abra_fleet_backend/.env');
  fs.mkdirSync(out, { recursive: true });
  const client = new MongoClient(process.env.MONGODB_URI, { serverSelectionTimeoutMS: 30000 });
  await client.connect();

  const dbs = (await client.db().admin().listDatabases()).databases.map((d) => d.name).filter((n) => !SKIP.has(n));
  console.log(`Backing up ${dbs.length} database(s): ${dbs.join(', ')}  (skipping: ${[...SKIP].join(', ')})`);

  const manifest = { takenAt: new Date().toISOString(), skipped: [...SKIP], databases: {} };
  let totalDocs = 0;

  for (const dbName of dbs) {
    const db = client.db(dbName);
    const cols = (await db.listCollections({}, { nameOnly: false }).toArray()).filter((c) => c.type === 'collection' && !c.name.startsWith('system.'));
    manifest.databases[dbName] = {};
    fs.mkdirSync(path.join(out, safe(dbName)), { recursive: true });

    for (const c of cols) {
      const base = path.join(out, safe(dbName), safe(c.name));
      const ws = fs.createWriteStream(base + '.ejsonl');
      let n = 0;
      for await (const doc of db.collection(c.name).find({}, { batchSize: 500 })) {
        const line = EJSON.stringify(doc, { relaxed: false }) + '\n';
        if (!ws.write(line)) await new Promise((r) => ws.once('drain', r));
        n++;
      }
      await new Promise((r) => ws.end(r));
      const idx = await db.collection(c.name).listIndexes().toArray();
      fs.writeFileSync(base + '.indexes.json', JSON.stringify({ options: c.options || {}, indexes: idx }, null, 2));
      manifest.databases[dbName][c.name] = { documents: n, sha256: await sha256(base + '.ejsonl'), indexes: idx.length };
      totalDocs += n;
    }
    console.log(`  ${dbName}: ${cols.length} collections done`);
  }

  fs.writeFileSync(path.join(out, 'MANIFEST.json'), JSON.stringify(manifest, null, 2));
  console.log(`\nBackup written to ${out}\nTotal documents: ${totalDocs}`);
  await client.close();
})().catch((e) => { console.error('STOPPED:', mask(e.message)); process.exit(1); });
