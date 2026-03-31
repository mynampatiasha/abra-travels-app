// Check which database is actually being used and list all collections
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function checkDatabase() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas\n');
    
    // List all databases
    const adminDb = client.db().admin();
    const { databases } = await adminDb.listDatabases();
    
    console.log('='*80);
    console.log('ALL DATABASES ON THIS CLUSTER:');
    console.log('='*80);
    databases.forEach((db, i) => {
      console.log(`${i + 1}. ${db.name} (${(db.sizeOnDisk / 1024 / 1024).toFixed(2)} MB)`);
    });
    
    // Check default database (no name specified = 'test')
    console.log('\n' + '='*80);
    console.log('CHECKING DEFAULT DATABASE (test):');
    console.log('='*80);
    const testDb = client.db('test');
    const testCollections = await testDb.listCollections().toArray();
    console.log(`Collections in 'test': ${testCollections.length}`);
    testCollections.forEach((col, i) => {
      console.log(`  ${i + 1}. ${col.name}`);
    });
    
    // Check if vehicles exist in test database
    const testVehicles = await testDb.collection('vehicles').countDocuments();
    console.log(`\nVehicles in 'test' database: ${testVehicles}`);
    
    // Check abra_fleet database
    console.log('\n' + '='*80);
    console.log('CHECKING ABRA_FLEET DATABASE:');
    console.log('='*80);
    const abraDb = client.db('abra_fleet');
    const abraCollections = await abraDb.listCollections().toArray();
    console.log(`Collections in 'abra_fleet': ${abraCollections.length}`);
    abraCollections.forEach((col, i) => {
      console.log(`  ${i + 1}. ${col.name}`);
    });
    
    // Check if vehicles exist in abra_fleet database
    const abraVehicles = await abraDb.collection('vehicles').countDocuments();
    console.log(`\nVehicles in 'abra_fleet' database: ${abraVehicles}`);
    
    if (abraVehicles > 0) {
      console.log('\n✅ Found vehicles in abra_fleet database!');
      const sampleVehicles = await abraDb.collection('vehicles').find({}).limit(3).toArray();
      console.log('\nSample vehicles:');
      sampleVehicles.forEach((v, i) => {
        console.log(`  ${i + 1}. ${v.name || v.vehicleNumber || v.registrationNumber} (ID: ${v._id})`);
      });
    }
    
    // Check which database the backend is using
    console.log('\n' + '='*80);
    console.log('BACKEND DATABASE CONFIGURATION:');
    console.log('='*80);
    console.log(`MONGODB_URI: ${MONGODB_URI}`);
    
    // Parse the URI to see if database name is specified
    const uriMatch = MONGODB_URI.match(/mongodb\+srv:\/\/[^\/]+\/([^?]+)/);
    if (uriMatch && uriMatch[1]) {
      console.log(`Database specified in URI: ${uriMatch[1]}`);
    } else {
      console.log('⚠️  No database specified in URI - will use "test" by default');
      console.log('💡 To fix: Add database name to URI like:');
      console.log('   mongodb+srv://user:pass@cluster.mongodb.net/abra_fleet?...');
    }
    
    console.log('='*80 + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkDatabase();
