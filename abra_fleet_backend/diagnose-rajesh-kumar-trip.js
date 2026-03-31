// Diagnose why Rajesh Kumar's trip doesn't show driver info
const { MongoClient, ObjectId } = require('mongodb');

async function diagnoseTrip() {
  const client = new MongoClient('mongodb://localhost:27017');
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    console.log('🔍 Finding Rajesh Kumar\'s roster...\n');
    
    // Find Rajesh Kumar's roster
    const roster = await db.collection('rosters').findOne({
      customerEmail: 'rajesh.kumar@infosys.com'
    });
    
    if (!roster) {
      console.log('❌ No roster found for rajesh.kumar@infosys.com');
      return;
    }
    
    console.log('📋 ROSTER FOUND:');
    console.log('   Roster ID:', roster._id);
    console.log('   Customer:', roster.customerName);
    console.log('   Status:', roster.status);
    console.log('   Vehicle Number:', roster.vehicleNumber || 'NOT SET');
    console.log('   Vehicle ID:', roster.vehicleId || 'NOT SET');
    console.log('   Driver Name:', roster.driverName || 'NOT SET');
    console.log('   Driver Phone:', roster.driverPhone || 'NOT SET');
    console.log('   Driver ID:', roster.driverId || 'NOT SET');
    console.log('   Assigned Driver Name:', roster.assignedDriverName || 'NOT SET');
    console.log('   Assigned Driver Phone:', roster.assignedDriverPhone || 'NOT SET');
    
    console.log('\n📦 FULL ROSTER OBJECT:');
    console.log(JSON.stringify(roster, null, 2));
    
    // Check if vehicle exists
    if (roster.vehicleId) {
      console.log('\n🚗 Checking vehicle...');
      const vehicle = await db.collection('vehicles').findOne({
        _id: new ObjectId(roster.vehicleId)
      });
      
      if (vehicle) {
        console.log('   ✅ Vehicle found:', vehicle.vehicleNumber || vehicle.name);
        console.log('   Assigned Driver ID:', vehicle.assignedDriverId || 'NOT SET');
      } else {
        console.log('   ❌ Vehicle not found');
      }
    }
    
    // Check if driver exists
    if (roster.driverId) {
      console.log('\n👤 Checking driver in users collection...');
      const driver = await db.collection('users').findOne({
        _id: new ObjectId(roster.driverId)
      });
      
      if (driver) {
        console.log('   ✅ Driver found:', driver.name);
        console.log('   Phone:', driver.phone || driver.phoneNumber || 'NOT SET');
      } else {
        console.log('   ❌ Driver not found in users collection');
        
        // Try drivers collection
        const driverAlt = await db.collection('drivers').findOne({
          _id: new ObjectId(roster.driverId)
        });
        
        if (driverAlt) {
          console.log('   ✅ Driver found in drivers collection');
          console.log('   Name:', driverAlt.personalInfo?.firstName, driverAlt.personalInfo?.lastName);
        }
      }
    } else {
      console.log('\n⚠️  No driverId set in roster');
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('DIAGNOSIS COMPLETE');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

diagnoseTrip();
