#!/usr/bin/env node
/**
 * Copy the Fleet database from the OLD Atlas cluster to the NEW one.
 *
 *   SOURCE  = MONGODB_URI in abra_fleet_backend/.env          (read-only, never modified)
 *   TARGET  = NEW_MONGODB_URI environment variable            (you type it; never stored or printed)
 *
 * The target URI MUST contain the database name, e.g.
 *   mongodb+srv://<user>:<password>@fleetcluster.xxxxx.mongodb.net/abra_fleet?retryWrites=true&w=majority
 *
 * Usage (from abra_fleet_backend/):
 *   node scripts/migrate-to-new-cluster.js                     # dry run: sizes + connectivity, writes NOTHING
 *   node scripts/migrate-to-new-cluster.js --apply             # copy everything into the (empty) target
 *   node scripts/migrate-to-new-cluster.js --apply --exclude=notifications,location_history
 *   node scripts/migrate-to-new-cluster.js --apply --resume    # continue after an interrupted run
 *   node scripts/migrate-to-new-cluster.js --apply --uri-file=D:/secrets/new-uri.txt   # read the target URL from a private file
 *
 * Safety rules built in:
 *   - the source is only ever read
 *   - refuses to run if source and target are the same cluster/database
 *   - refuses to write into a target that already has data (unless --resume, which skips
 *     collections that are already fully copied and aborts on partial ones)
 *   - aborts if the data would not fit the 512 MB free tier (override with --force)
 *   - credentials are masked in all output
 */
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { MongoClient } = require('mongodb');

const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
const opt = (n) => (args.find((a) => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const APPLY = flag('apply');
const RESUME = flag('resume');
const FORCE = flag('force');
const EXCLUDE = new Set(opt('exclude').split(',').map((s) => s.trim()).filter(Boolean));
const BATCH = 500;
const FREE_TIER_LIMIT_MB = 512;
// Databases that belong to OTHER applications on the old cluster. This tool refuses to touch them.
const PROTECTED_DBS = new Set(['abra_finance_module', 'abra_fleet_management', 'abrafleet', 'sample_mflix', 'admin', 'local']);

// Optional: read the target URL from a private file (keeps the password out of the shell history and chat)
const fs = require('fs');
const uriFile = opt('uri-file');
if (uriFile && !process.env.NEW_MONGODB_URI) {
  const raw = fs.readFileSync(uriFile, 'utf8').trim();
  process.env.NEW_MONGODB_URI = raw.replace(/^NEW_MONGODB_URI=/, '').replace(/^["']|["']$/g, '').trim();
}

const mask = (s) => String(s).replace(/\/\/[^@/]*@/g, '//***:***@');
const mb = (n) => (n / 1048576).toFixed(1);
const dbNameFromUri = (uri) => {
  const m = uri.match(/^mongodb(?:\+srv)?:\/\/[^/]+\/([^?]*)/);
  return m && m[1] ? decodeURIComponent(m[1]) : '';
};
const hostsFromUri = (uri) => (uri.match(/^mongodb(?:\+srv)?:\/\/(?:[^@/]*@)?([^/?]+)/) || [])[1] || '';

(async () => {
  const SRC = process.env.MONGODB_URI;
  const DST = process.env.NEW_MONGODB_URI;
  if (!SRC) throw new Error('MONGODB_URI (source) is not set in abra_fleet_backend/.env');

  const srcName = dbNameFromUri(SRC);
  if (srcName !== 'abra_fleet' || PROTECTED_DBS.has(srcName)) {
    throw new Error(`Source database must be 'abra_fleet' (got '${srcName}'). Databases of other apps, e.g. abra_finance_module, are never touched.`);
  }
  console.log(`Mode: ${APPLY ? 'APPLY (writes to target)' : 'DRY RUN (writes nothing)'}${RESUME ? ' + resume' : ''}`);

  const src = new MongoClient(SRC, { serverSelectionTimeoutMS: 30000 });
  await src.connect();
  const sdb = src.db(srcName || undefined);
  const cols = (await sdb.listCollections({}, { nameOnly: false }).toArray())
    .filter((c) => c.type === 'collection' && !c.name.startsWith('system.') && !EXCLUDE.has(c.name));

  // ---- size the job -------------------------------------------------------
  const plan = [];
  let totalBytes = 0;
  for (const c of cols) {
    const st = await sdb.command({ collStats: c.name }).catch(() => ({ count: 0, size: 0, totalIndexSize: 0 }));
    plan.push({ name: c.name, docs: st.count || 0, bytes: (st.size || 0) + (st.totalIndexSize || 0), capped: !!(c.options && c.options.capped), options: c.options || {} });
    totalBytes += (st.size || 0) + (st.totalIndexSize || 0);
  }
  console.log(`Source db "${sdb.databaseName}": ${plan.length} collections, ${plan.reduce((a, p) => a + p.docs, 0)} documents, ~${mb(totalBytes)} MB (data+indexes)`);
  if (EXCLUDE.size) console.log(`Excluded: ${[...EXCLUDE].join(', ')}`);
  if (totalBytes / 1048576 > FREE_TIER_LIMIT_MB * 0.8 && !FORCE) {
    throw new Error(`Data (~${mb(totalBytes)} MB) is over 80% of the ${FREE_TIER_LIMIT_MB} MB free tier. Exclude collections or pass --force.`);
  }

  if (!DST) {
    console.log('\nNEW_MONGODB_URI is not set, so only the source was checked.');
    console.log('Set it in YOUR terminal (so the password never appears in a file or chat), then re-run:');
    console.log('  PowerShell:  $env:NEW_MONGODB_URI = "mongodb+srv://USER:PASSWORD@HOST/abra_fleet?retryWrites=true&w=majority"');
    console.log('  Git Bash  :  export NEW_MONGODB_URI=\'mongodb+srv://USER:PASSWORD@HOST/abra_fleet?retryWrites=true&w=majority\'');
    await src.close();
    return;
  }

  const dstName = dbNameFromUri(DST);
  if (!dstName) throw new Error('NEW_MONGODB_URI has no database name. It must end like  .../abra_fleet?retryWrites=true&w=majority');
  if (hostsFromUri(DST) === hostsFromUri(SRC) && dstName === srcName) {
    throw new Error('Source and target are the same cluster and database. Refusing to continue.');
  }

  const dst = new MongoClient(DST, { serverSelectionTimeoutMS: 30000 });
  await dst.connect();
  const ddb = dst.db(dstName);
  console.log(`Target db "${dstName}" on ${hostsFromUri(DST)}: connected OK`);

  const existing = (await ddb.listCollections().toArray()).filter((c) => !c.name.startsWith('system.'));
  const existingCounts = {};
  for (const c of existing) existingCounts[c.name] = await ddb.collection(c.name).estimatedDocumentCount();
  const nonEmpty = Object.entries(existingCounts).filter(([, n]) => n > 0);
  if (nonEmpty.length && !RESUME) {
    throw new Error(`Target already contains data (${nonEmpty.map(([k, n]) => `${k}:${n}`).slice(0, 5).join(', ')}...). Use an empty database, or --resume to continue an interrupted copy.`);
  }

  if (!APPLY) {
    console.log('\nDRY RUN complete: the source is readable and the target is reachable and empty. Nothing was written.');
    console.log('Run again with --apply to copy.');
    await src.close(); await dst.close();
    return;
  }

  // ---- copy ---------------------------------------------------------------
  const report = [];
  for (const p of plan) {
    const sc = sdb.collection(p.name);
    const dc = ddb.collection(p.name);
    const before = existingCounts[p.name] || 0;
    if (RESUME && before === p.docs && p.docs > 0) { report.push({ collection: p.name, source: p.docs, target: before, status: 'skipped (already copied)' }); continue; }
    if (before > 0 && before !== p.docs) throw new Error(`Collection ${p.name} is partially copied (${before}/${p.docs}). Drop that one collection in Atlas and re-run with --resume.`);

    // Mirror the collection itself (also empty ones with no indexes), with its original options
    await ddb.createCollection(p.name, p.options).catch((e) => { if (e.code !== 48) throw e; }); // 48 = already exists

    let copied = 0;
    let buf = [];
    const flush = async () => {
      if (!buf.length) return;
      try { await dc.insertMany(buf, { ordered: false }); }
      catch (e) { if (!(e.code === 11000 || (e.writeErrors || []).every((w) => w.code === 11000))) throw e; }
      copied += buf.length; buf = [];
    };
    const cursor = sc.find({}, { batchSize: BATCH });
    for await (const doc of cursor) { buf.push(doc); if (buf.length >= BATCH) await flush(); }
    await flush();

    // indexes (everything except the automatic _id index)
    const idx = (await sc.listIndexes().toArray()).filter((i) => i.name !== '_id_');
    let idxOk = 0, idxErr = [];
    for (const i of idx) {
      const { key, name, v, ns, ...options } = i;
      try { await dc.createIndex(key, { name, ...options }); idxOk++; }
      catch (e) { idxErr.push(`${name}: ${e.message.slice(0, 60)}`); }
    }
    const after = await dc.countDocuments({});
    report.push({ collection: p.name, source: p.docs, target: after, indexes: `${idxOk}/${idx.length}`, status: after === p.docs && !idxErr.length ? 'OK' : 'CHECK ' + idxErr.join('; ') });
    process.stdout.write(`  ${p.name}: ${after}/${p.docs}\n`);
  }

  console.log('\n=== SUMMARY ===');
  console.table(report);
  const bad = report.filter((r) => r.status !== 'OK' && !String(r.status).startsWith('skipped'));
  console.log(bad.length ? `${bad.length} collection(s) need attention (see CHECK rows).` : 'All collections copied and counts match.');
  await src.close(); await dst.close();
})().catch((e) => { console.error('\nSTOPPED:', mask(e.message)); process.exit(1); });
