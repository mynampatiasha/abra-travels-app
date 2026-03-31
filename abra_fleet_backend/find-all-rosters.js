// Find all rosters in database
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require('./serviceAccountKey.json')),
    databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
  });
}

const db = admin.firestore();

async function findAllRosters() {
  try {
    console.log('🔍 Finding all rosters in database...\n');
    
    // Get all rosters
    const rostersSnapshot = await db.collection('rosters').get();
    
    console.log(`📊 Total rosters found: ${rostersSnapshot.size}\n`);
    
    if (rostersSnapshot.size === 0) {
      console.log('✅ No rosters in database');
      process.exit(0);
      return;
    }
    
    // Display all rosters
    console.log('📋 All Rosters:');
    rostersSnapshot.forEach((doc, index) => {
      const roster = doc.data();
      console.log(`\n${index + 1}. Document ID: ${doc.id}`);
      console.log(`   Customer Name: ${roster.customerName || 'N/A'}`);
      console.log(`   Customer Email: ${roster.customerEmail || 'N/A'}`);
      console.log(`   Vehicle: ${roster.vehicleNumber || 'N/A'}`);
      console.log(`   Driver: ${roster.driverName || 'N/A'}`);
      console.log(`   Status: ${roster.status || 'N/A'}`);
      console.log(`   Valid From: ${roster.validFrom || 'N/A'}`);
      console.log(`   Valid To: ${roster.validTo || 'N/A'}`);
    });
    
    console.log('\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

findAllRosters();
