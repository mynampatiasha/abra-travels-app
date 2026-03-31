// verify-roster-save-flow.js
// Check the complete roster save and assignment flow

const { MongoClient } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const dbName = 'abra_fleet';

async function verifyRosterFlow() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    const rostersCollection = db.collection('rosters');
    
    console.log('=' .repeat(80));
    console.log('ROSTER SAVE & ASSIGNMENT FLOW VERIFICATION');
    console.log('='.repeat(80));
    
    // 1. Check rosters by status
    console.log('\n📊 STEP 1: ROSTERS BY STATUS');
    console.log('-'.repeat(80));
    
    const statusCounts = await rostersCollection.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]).toArray();
    
    console.log('\nStatus Distribution:');
    let totalRosters = 0;
    for (const status of statusCounts) {
      console.log(`   ${status._id || 'null'}: ${status.count} rosters`);
      totalRosters += status.count;
    }
    console.log(`\n   TOTAL: ${totalRosters} rosters`);
    
    // 2. Check pending_assignment rosters (from bulk import)
    console.log('\n\n📋 STEP 2: PENDING ASSIGNMENT ROSTERS (From Bulk Import)');
    console.log('-'.repeat(80));
    
    const pendingRosters = await rostersCollection.find({
      status: 'pending_assignment'
    }).limit(5).toArray();
    
    console.log(`\nFound ${pendingRosters.length} pending rosters (showing first 5):\n`);
    
    for (let i = 0; i < pendingRosters.length; i++) {
      const roster = pendingRosters[i];
      console.log(`${i + 1}. Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
      console.log(`   Email: ${roster.customerEmail || roster.employeeDetails?.email || 'Unknown'}`);
      console.log(`   Office: ${roster.officeLocation || 'Unknown'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Created: ${roster.createdAt || 'Unknown'}`);
      console.log(`   Has Driver? ${roster.assignedDriver ? 'YES' : 'NO'}`);
      console.log(`   Has Vehicle? ${roster.assignedVehicle ? 'YES' : 'NO'}`);
      console.log('');
    }
    
    // 3. Check assigned rosters (after route optimization)
    console.log('\n🚗 STEP 3: ASSIGNED ROSTERS (After Route Optimization)');
    console.log('-'.repeat(80));
    
    const assignedRosters = await rostersCollection.find({
      status: 'assigned'
    }).limit(5).toArray();
    
    console.log(`\nFound ${assignedRosters.length} assigned rosters (showing first 5):\n`);
    
    for (let i = 0; i < assignedRosters.length; i++) {
      const roster = assignedRosters[i];
      console.log(`${i + 1}. Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
      console.log(`   Email: ${roster.customerEmail || roster.employeeDetails?.email || 'Unknown'}`);
      console.log(`   Office: ${roster.officeLocation || 'Unknown'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Assigned Driver: ${roster.assignedDriver?.name || roster.driverName || 'NONE'}`);
      console.log(`   Assigned Vehicle: ${roster.assignedVehicle?.registrationNumber || roster.vehicleNumber || 'NONE'}`);
      console.log(`   Assigned At: ${roster.assignedAt || roster.assignmentDate || 'Unknown'}`);
      console.log('');
    }
    
    // 4. Verify the flow
    console.log('\n✅ STEP 4: FLOW VERIFICATION');
    console.log('-'.repeat(80));
    
    const pendingCount = await rostersCollection.countDocuments({ status: 'pending_assignment' });
    const assignedCount = await rostersCollection.countDocuments({ status: 'assigned' });
    const assignedWithDriver = await rostersCollection.countDocuments({ 
      status: 'assigned',
      $or: [
        { 'assignedDriver': { $exists: true, $ne: null } },
        { 'driverName': { $exists: true, $ne: null, $ne: '' } }
      ]
    });
    const assignedWithVehicle = await rostersCollection.countDocuments({ 
      status: 'assigned',
      $or: [
        { 'assignedVehicle': { $exists: true, $ne: null } },
        { 'vehicleNumber': { $exists: true, $ne: null, $ne: '' } }
      ]
    });
    
    console.log('\n📊 Summary:');
    console.log(`   Pending Assignment: ${pendingCount} rosters`);
    console.log(`   Assigned: ${assignedCount} rosters`);
    console.log(`   Assigned WITH Driver: ${assignedWithDriver} rosters`);
    console.log(`   Assigned WITH Vehicle: ${assignedWithVehicle} rosters`);
    
    console.log('\n\n🔍 ANALYSIS:');
    console.log('-'.repeat(80));
    
    if (pendingCount > 0) {
      console.log(`✅ ${pendingCount} rosters are saved in database with status "pending_assignment"`);
      console.log('   These were created during BULK IMPORT');
      console.log('   They are waiting for admin to assign driver/vehicle');
    }
    
    if (assignedCount > 0) {
      console.log(`\n✅ ${assignedCount} rosters have status "assigned"`);
      if (assignedWithDriver === assignedCount && assignedWithVehicle === assignedCount) {
        console.log('   ✅ ALL assigned rosters have driver AND vehicle');
        console.log('   These were properly assigned through ROUTE OPTIMIZATION');
      } else {
        console.log(`   ⚠️  WARNING: Some assigned rosters are missing driver/vehicle:`);
        console.log(`      - ${assignedCount - assignedWithDriver} rosters missing driver`);
        console.log(`      - ${assignedCount - assignedWithVehicle} rosters missing vehicle`);
        console.log('   These may have been manually marked as "assigned" without proper assignment');
      }
    }
    
    console.log('\n\n📝 CORRECT FLOW:');
    console.log('-'.repeat(80));
    console.log('1. Client imports rosters via Bulk Import');
    console.log('   → Rosters saved with status: "pending_assignment"');
    console.log('   → NO driver or vehicle assigned yet');
    console.log('');
    console.log('2. Admin goes to "Pending Rosters" screen');
    console.log('   → Sees all rosters with status: "pending_assignment"');
    console.log('');
    console.log('3. Admin clicks "Route Optimization"');
    console.log('   → System assigns driver and vehicle');
    console.log('   → Status changes to: "assigned"');
    console.log('   → Driver and vehicle fields are populated');
    console.log('   → Notifications sent to customer and driver');
    console.log('');
    console.log('4. Rosters now appear in "Assigned Rosters" screen');
    console.log('   → Query: status = "assigned"');
    console.log('   → Shows driver name, vehicle number, etc.');
    
    console.log('\n' + '='.repeat(80));
    console.log('VERIFICATION COMPLETE');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

verifyRosterFlow();
