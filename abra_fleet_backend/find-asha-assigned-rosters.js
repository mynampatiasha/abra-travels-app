// Find rosters assigned to Asha driver using correct field structure
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function findAshaAssignedRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // First, get Asha's driver record
    const driver = await db.collection('drivers').findOne({
      email: 'ashamynampati2003@gmail.com'
    });
    
    if (!driver) {
      console.log('❌ Driver not found!');
      return;
    }
    
    console.log('\n✅ Driver found:');
    console.log(`   Name: ${driver.name}`);
    console.log(`   Email: ${driver.email}`);
    console.log(`   MongoDB _id: ${driver._id}`);
    console.log(`   Firebase UID: ${driver.uid}`);
    
    // Search for rosters using assignedDriver field (MongoDB _id)
    console.log('\n🔍 Searching for rosters with assignedDriver = driver._id...');
    
    const rostersByDriverId = await db.collection('rosters').find({
      assignedDriver: driver._id.toString()
    }).toArray();
    
    console.log(`   Found: ${rostersByDriverId.length} rosters`);
    
    // Also try with ObjectId
    const rostersByDriverObjectId = await db.collection('rosters').find({
      assignedDriver: driver._id
    }).toArray();
    
    console.log(`   Found (ObjectId): ${rostersByDriverObjectId.length} rosters`);
    
    // Combine and deduplicate
    const allRosters = [...rostersByDriverId, ...rostersByDriverObjectId];
    const uniqueRosters = Array.from(new Map(allRosters.map(r => [r._id.toString(), r])).values());
    
    console.log('\n' + '='.repeat(80));
    console.log(`📋 TOTAL ROSTERS ASSIGNED TO ASHA: ${uniqueRosters.length}`);
    console.log('='.repeat(80));
    
    if (uniqueRosters.length === 0) {
      console.log('\n❌ NO ROSTERS ASSIGNED!');
      console.log('\n💡 This means admin has NOT assigned any rosters to this driver yet.');
      return;
    }
    
    // Group by status and date
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const active = [];
    const cancelled = [];
    const completed = [];
    const todayRosters = [];
    
    for (const roster of uniqueRosters) {
      if (roster.status === 'cancelled') {
        cancelled.push(roster);
      } else if (roster.status === 'completed') {
        completed.push(roster);
      } else {
        active.push(roster);
      }
      
      // Check if roster is for today
      const startDate = new Date(roster.startDate);
      const endDate = new Date(roster.endDate);
      if (startDate <= today && endDate >= today) {
        todayRosters.push(roster);
      }
    }
    
    console.log('\n📊 ROSTER BREAKDOWN:');
    console.log(`   Active: ${active.length}`);
    console.log(`   Cancelled: ${cancelled.length}`);
    console.log(`   Completed: ${completed.length}`);
    console.log(`   For Today: ${todayRosters.length}`);
    
    if (todayRosters.length > 0) {
      console.log('\n' + '='.repeat(80));
      console.log('📅 ROSTERS FOR TODAY');
      console.log('='.repeat(80));
      
      for (const roster of todayRosters) {
        // Get customer details
        const customer = await db.collection('users').findOne({
          uid: roster.userId
        });
        
        console.log(`\n  Roster ID: ${roster._id}`);
        console.log(`  Customer: ${customer?.name || roster.userId}`);
        console.log(`  Email: ${customer?.email || 'N/A'}`);
        console.log(`  Type: ${roster.rosterType}`);
        console.log(`  Office: ${roster.officeLocation}`);
        console.log(`  Time: ${roster.startTime} - ${roster.endTime}`);
        console.log(`  Status: ${roster.status}`);
        console.log(`  Period: ${new Date(roster.startDate).toDateString()} to ${new Date(roster.endDate).toDateString()}`);
        
        if (roster.locations) {
          if (roster.locations.loginPickup) {
            console.log(`  Pickup: ${roster.locations.loginPickup.address}`);
          }
          if (roster.locations.logoutDrop) {
            console.log(`  Drop: ${roster.locations.logoutDrop.address}`);
          }
        }
        
        // Get vehicle details
        if (roster.assignedVehicle) {
          const vehicle = await db.collection('vehicles').findOne({
            _id: new ObjectId(roster.assignedVehicle)
          });
          if (vehicle) {
            console.log(`  Vehicle: ${vehicle.registrationNumber} (${vehicle.model})`);
          }
        }
      }
    }
    
    if (active.length > 0) {
      console.log('\n' + '='.repeat(80));
      console.log('📅 ACTIVE ROSTERS (All)');
      console.log('='.repeat(80));
      
      for (const roster of active.slice(0, 10)) {
        const customer = await db.collection('users').findOne({
          uid: roster.userId
        });
        
        console.log(`\n  ${new Date(roster.startDate).toDateString()} to ${new Date(roster.endDate).toDateString()}`);
        console.log(`  Customer: ${customer?.name || roster.userId}`);
        console.log(`  Type: ${roster.rosterType} | Status: ${roster.status}`);
      }
      
      if (active.length > 10) {
        console.log(`\n  ... and ${active.length - 10} more`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

findAshaAssignedRosters();
