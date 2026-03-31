const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function testPendingRostersDriverPhone() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Get assigned rosters (these should show in "Assigned" tab of Pending Rosters screen)
    console.log('📋 Fetching assigned rosters from database...\n');
    const rosters = await db.collection('rosters')
      .find({ status: 'assigned' })
      .limit(5)
      .toArray();
    
    console.log(`Found ${rosters.length} assigned rosters\n`);
    console.log('='.repeat(80));
    
    rosters.forEach((roster, index) => {
      console.log(`\n${index + 1}. Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   assignedDriverName: ${roster.assignedDriverName || 'Not set'}`);
      console.log(`   driverName: ${roster.driverName || 'Not set'}`);
      console.log(`   driverPhone: ${roster.driverPhone || 'NOT SET ❌'}`);
      console.log(`   assignedVehicleReg: ${roster.assignedVehicleReg || 'Not set'}`);
      console.log(`   vehicleNumber: ${roster.vehicleNumber || 'Not set'}`);
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('\n✅ Test complete!');
    console.log('\nExpected behavior after backend fix:');
    console.log('- /api/roster/admin/pending endpoint should return:');
    console.log('  • driverName field');
    console.log('  • driverPhone field (e.g., 9123456789)');
    console.log('  • vehicleNumber field');
    console.log('\nTo test:');
    console.log('1. Restart backend: node index.js');
    console.log('2. In Flutter app, go to: Customer Management → Pending Rosters');
    console.log('3. Switch to "Assigned" tab');
    console.log('4. Click on any assigned roster');
    console.log('5. Check Assignment section shows:');
    console.log('   - Driver: Rajesh Kumar');
    console.log('   - Driver Phone: 9123456789 ✅');
    console.log('   - Vehicle: KA01AB1240');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testPendingRostersDriverPhone();
