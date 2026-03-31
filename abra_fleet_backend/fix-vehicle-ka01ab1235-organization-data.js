// fix-vehicle-ka01ab1235-organization-data.js
// Fix organization data for existing customers in vehicle KA01AB1235

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixVehicleOrganizationData() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find vehicle by ID (the one with 7 assigned customers from logs)
    const vehicleId = '68ddeb3f4eff4fbe00488ec8'; // From test-feasibility-check.js output
    
    const vehicle = await db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    if (!vehicle) {
      console.log(`❌ Vehicle ${vehicleId} not found`);
      return;
    }
    
    console.log(`\n🚗 Vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
    console.log(`   ID: ${vehicle._id}`);
    console.log(`   Assigned customers: ${vehicle.assignedCustomers?.length || 0}`);
    
    // Find all assigned rosters for this vehicle
    const assignedRosters = await db.collection('rosters').find({
      vehicleId: vehicle._id.toString(),
      status: 'assigned'
    }).toArray();
    
    console.log(`\n📋 Found ${assignedRosters.length} assigned rosters`);
    
    if (assignedRosters.length === 0) {
      console.log('✅ No rosters to fix');
      return;
    }
    
    console.log('\n🔍 Checking organization data...\n');
    
    let fixedCount = 0;
    let alreadyOkCount = 0;
    
    for (const roster of assignedRosters) {
      const currentOrg = roster.organization || 
                        roster.organizationName || 
                        roster.companyName || 
                        roster.company;
      
      const employeeOrg = roster.employeeDetails?.organization || 
                         roster.employeeDetails?.company;
      
      console.log(`📄 Roster: ${roster.customerName || 'Unknown'}`);
      console.log(`   Current organization field: ${currentOrg || 'MISSING'}`);
      console.log(`   Employee details organization: ${employeeOrg || 'MISSING'}`);
      
      if (!currentOrg && employeeOrg) {
        // Fix: Copy organization from employeeDetails to top level
        console.log(`   ✅ Fixing: Setting organization to "${employeeOrg}"`);
        
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          {
            $set: {
              organization: employeeOrg,
              organizationName: employeeOrg,
              updatedAt: new Date()
            }
          }
        );
        
        fixedCount++;
      } else if (currentOrg) {
        console.log(`   ✅ Already has organization: ${currentOrg}`);
        alreadyOkCount++;
      } else {
        console.log(`   ⚠️  WARNING: No organization data found anywhere!`);
      }
      
      console.log('');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 SUMMARY');
    console.log('='.repeat(80));
    console.log(`Total rosters: ${assignedRosters.length}`);
    console.log(`Fixed: ${fixedCount}`);
    console.log(`Already OK: ${alreadyOkCount}`);
    console.log(`Still missing: ${assignedRosters.length - fixedCount - alreadyOkCount}`);
    console.log('='.repeat(80));
    
    if (fixedCount > 0) {
      console.log('\n✅ Organization data has been fixed!');
      console.log('   Now the compatibility check will work correctly.');
      console.log('   Try assigning the route again.');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Disconnected from MongoDB');
  }
}

fixVehicleOrganizationData();
