// Test Asha's driver route
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function testAshaDriverRoute() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Asha's email
    const driverEmail = 'ashamynampati2003@gmail.com';
    
    console.log('\n🔍 Checking driver:', driverEmail);
    
    // Find driver in drivers collection
    const driver = await db.collection('drivers').findOne({ 
      email: driverEmail 
    });
    
    if (!driver) {
      console.log('❌ Driver not found in drivers collection');
      console.log('   Creating driver entry...');
      
      await db.collection('drivers').insertOne({
        uid: 'asha_driver_uid', // This should match Firebase UID
        email: driverEmail,
        name: 'Asha Mynampati',
        phone: '+91 98765 43210',
        status: 'available',
        createdAt: new Date()
      });
      
      console.log('✅ Driver created');
    } else {
      console.log('✅ Driver found:', driver.name);
      console.log('   UID:', driver.uid);
    }
    
    // Check for today's rosters
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const rosters = await db.collection('rosters').find({
      driverId: driver?.uid || 'asha_driver_uid',
      scheduledDate: {
        $gte: today,
        $lt: tomorrow
      }
    }).toArray();
    
    console.log(`\n📋 Found ${rosters.length} roster(s) for today`);
    
    if (rosters.length === 0) {
      console.log('\n⚠️  No rosters assigned for today');
      console.log('   The driver dashboard will show "No route assigned"');
    } else {
      rosters.forEach((roster, index) => {
        console.log(`\n${index + 1}. Roster ID: ${roster._id}`);
        console.log(`   Customer: ${roster.customerId}`);
        console.log(`   Type: ${roster.rosterType}`);
        console.log(`   Time: ${roster.scheduledTime}`);
        console.log(`   Status: ${roster.status}`);
      });
    }
    
    // Check for assigned vehicle
    const activeRoster = rosters.find(r => r.vehicleId);
    if (activeRoster && activeRoster.vehicleId) {
      const vehicle = await db.collection('vehicles').findOne({
        _id: activeRoster.vehicleId
      });
      
      if (vehicle) {
        console.log('\n🚗 Assigned Vehicle:');
        console.log(`   Registration: ${vehicle.registrationNumber}`);
        console.log(`   Model: ${vehicle.model}`);
      }
    } else {
      console.log('\n⚠️  No vehicle assigned');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testAshaDriverRoute();
