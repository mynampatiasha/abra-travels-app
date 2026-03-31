// Check rosters for Rajesh Kumar (ashamynampati24@gmail.com)
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkRajeshKumarRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 CHECKING DRIVER: Rajesh Kumar');
    console.log('Email: ashamynampati24@gmail.com');
    console.log('='.repeat(70));
    
    // Find driver by email
    const driver = await db.collection('drivers').findOne({
      email: 'ashamynampati24@gmail.com'
    });
    
    if (!driver) {
      console.log('❌ Driver not found!');
      return;
    }
    
    console.log('\n✅ DRIVER FOUND:');
    console.log(`   Name: ${driver.name}`);
    console.log(`   Email: ${driver.email}`);
    console.log(`   Driver Code: ${driver.driverCode || 'N/A'}`);
    console.log(`   MongoDB _id: ${driver._id}`);
    console.log(`   Firebase UID: ${driver.uid || 'N/A'}`);
    console.log(`   Status: ${driver.status}`);
    
    // Check for rosters assigned to this driver
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    console.log(`\n📅 CHECKING ROSTERS FOR TODAY: ${today.toISOString().split('T')[0]}`);
    console.log('='.repeat(70));
    
    // Find rosters by driver MongoDB _id
    const rosters = await db.collection('rosters').find({
      assignedDriver: driver._id.toString(),
      startDate: { $lte: today },
      endDate: { $gte: today },
      status: { $nin: ['cancelled', 'completed'] }
    }).toArray();
    
    console.log(`\n📋 FOUND ${rosters.length} ROSTER(S) FOR TODAY`);
    
    if (rosters.length === 0) {
      console.log('\n⚠️  NO ROSTERS ASSIGNED FOR TODAY');
      
      // Check if there are ANY rosters for this driver (past or future)
      const allRosters = await db.collection('rosters').find({
        assignedDriver: driver._id.toString()
      }).toArray();
      
      console.log(`\n📊 TOTAL ROSTERS (ALL TIME): ${allRosters.length}`);
      
      if (allRosters.length > 0) {
        console.log('\n📅 ROSTER DATE RANGES:');
        allRosters.forEach((roster, index) => {
          console.log(`   ${index + 1}. ${roster.startDate.toISOString().split('T')[0]} to ${roster.endDate.toISOString().split('T')[0]} - Status: ${roster.status}`);
        });
      }
    } else {
      console.log('\n✅ ROSTER DETAILS:');
      
      for (let i = 0; i < rosters.length; i++) {
        const roster = rosters[i];
        console.log(`\n   📍 ROSTER ${i + 1}:`);
        console.log(`      ID: ${roster._id}`);
        console.log(`      Customer UID: ${roster.userId}`);
        console.log(`      Type: ${roster.rosterType}`);
        console.log(`      Time: ${roster.startTime} - ${roster.endTime}`);
        console.log(`      Status: ${roster.status}`);
        console.log(`      Vehicle: ${roster.assignedVehicle || 'N/A'}`);
        console.log(`      Office: ${roster.officeLocation || 'N/A'}`);
        
        // Get customer details
        const customer = await db.collection('users').findOne({ uid: roster.userId });
        if (customer) {
          console.log(`      Customer: ${customer.name} (${customer.email})`);
          console.log(`      Phone: ${customer.phone || 'N/A'}`);
        }
        
        // Show locations
        if (roster.locations) {
          console.log(`      Pickup: ${roster.locations.loginPickup?.address || 'N/A'}`);
          console.log(`      Drop: ${roster.locations.logoutDrop?.address || roster.officeLocation || 'N/A'}`);
        }
      }
      
      // Get vehicle details
      if (rosters[0].assignedVehicle) {
        const { ObjectId } = require('mongodb');
        const vehicle = await db.collection('vehicles').findOne({
          _id: new ObjectId(rosters[0].assignedVehicle)
        });
        
        if (vehicle) {
          console.log('\n🚗 ASSIGNED VEHICLE:');
          console.log(`   Registration: ${vehicle.registrationNumber}`);
          console.log(`   Model: ${vehicle.make} ${vehicle.model}`);
          console.log(`   Capacity: ${vehicle.capacity} seats`);
          console.log(`   Status: ${vehicle.status}`);
        }
      }
    }
    
    console.log('\n' + '='.repeat(70));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRajeshKumarRosters();
