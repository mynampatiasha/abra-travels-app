const admin = require('./services/firebase_admin');
require('dotenv').config();

async function checkFirebaseRosters() {
  try {
    console.log('✅ Checking Firebase Realtime Database for rosters\n');
    console.log('='.repeat(80));
    
    const db = admin.database();
    
    // Check rosters node
    const rostersRef = db.ref('rosters');
    const rostersSnapshot = await rostersRef.once('value');
    const rostersData = rostersSnapshot.val();
    
    if (rostersData) {
      const rosterKeys = Object.keys(rostersData);
      console.log(`\n📋 Found ${rosterKeys.length} rosters in Firebase\n`);
      
      // Show first 10 rosters
      const sampleKeys = rosterKeys.slice(0, 10);
      
      sampleKeys.forEach((key, index) => {
        const roster = rostersData[key];
        console.log(`\n${index + 1}. Roster Key: ${key}`);
        console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
        console.log(`   Status: ${roster.status || 'N/A'}`);
        console.log(`   Vehicle: ${roster.vehicleNumber || 'Not assigned'}`);
        console.log(`   Driver: ${roster.driverName || 'Not assigned'}`);
      });
      
      // Count by status
      const statusCounts = {};
      rosterKeys.forEach(key => {
        const status = rostersData[key].status || 'unknown';
        statusCounts[status] = (statusCounts[status] || 0) + 1;
      });
      
      console.log('\n' + '='.repeat(80));
      console.log('\n📊 Rosters by status:');
      Object.entries(statusCounts).forEach(([status, count]) => {
        console.log(`   ${status}: ${count}`);
      });
      
    } else {
      console.log('\n❌ NO rosters found in Firebase Realtime Database');
    }
    
    // Check trips node (alternative location)
    console.log('\n' + '='.repeat(80));
    console.log('\n🔍 Checking trips node...\n');
    
    const tripsRef = db.ref('trips');
    const tripsSnapshot = await tripsRef.once('value');
    const tripsData = tripsSnapshot.val();
    
    if (tripsData) {
      const tripKeys = Object.keys(tripsData);
      console.log(`📋 Found ${tripKeys.length} trips in Firebase`);
    } else {
      console.log('❌ NO trips found in Firebase');
    }
    
    // Check customers node
    console.log('\n' + '='.repeat(80));
    console.log('\n🔍 Checking customers node...\n');
    
    const customersRef = db.ref('customers');
    const customersSnapshot = await customersRef.once('value');
    const customersData = customersSnapshot.val();
    
    if (customersData) {
      const customerKeys = Object.keys(customersData);
      console.log(`👥 Found ${customerKeys.length} customers in Firebase`);
    } else {
      console.log('❌ NO customers found in Firebase');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n💡 CONCLUSION:');
    console.log('   The pending rosters screen is likely reading from:');
    console.log('   1. Firebase Realtime Database (if rosters exist there)');
    console.log('   2. Local Flutter cache/state');
    console.log('   3. Firestore (another possibility)');
    console.log('\n   But MongoDB has NO rosters, which is why assignment fails!');
    
    process.exit(0);
    
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

checkFirebaseRosters();
