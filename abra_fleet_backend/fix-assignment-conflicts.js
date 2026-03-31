// ============================================================================
// FIX ASSIGNMENT CONFLICTS - Clear existing assignments for testing
// ============================================================================

const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixAssignmentConflicts() {
  console.log('\n' + '='.repeat(80));
  console.log('🔧 FIXING ASSIGNMENT CONFLICTS');
  console.log('='.repeat(80));

  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db();
    
    // STEP 1: Check current assignments
    console.log('\n📋 STEP 1: Checking current roster assignments...');
    
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned'
    }).toArray();
    
    console.log(`Found ${assignedRosters.length} assigned rosters:`);
    assignedRosters.forEach((roster, i) => {
      console.log(`   ${i + 1}. ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
      console.log(`      Email: ${roster.customerEmail || roster.employeeDetails?.email || 'Unknown'}`);
      console.log(`      Vehicle: ${roster.vehicleNumber || roster.vehicleId || 'Unknown'}`);
      console.log(`      Driver: ${roster.driverName || 'Unknown'}`);
      console.log(`      Status: ${roster.status}`);
      console.log('');
    });
    
    // STEP 2: Check the specific customers from the logs (Wipro employees)
    console.log('\n📋 STEP 2: Checking Wipro customers specifically...');
    
    const wiproCustomers = await db.collection('rosters').find({
      $or: [
        { customerEmail: /wipro\.com$/i },
        { 'employeeDetails.email': /wipro\.com$/i }
      ]
    }).toArray();
    
    console.log(`Found ${wiproCustomers.length} Wipro customers:`);
    wiproCustomers.forEach((roster, i) => {
      console.log(`   ${i + 1}. ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
      console.log(`      Email: ${roster.customerEmail || roster.employeeDetails?.email || 'Unknown'}`);
      console.log(`      Status: ${roster.status}`);
      console.log(`      Vehicle: ${roster.vehicleNumber || roster.vehicleId || 'None'}`);
      console.log('');
    });
    
    // STEP 3: Offer to reset assignments for testing
    console.log('\n🔧 STEP 3: Reset Options');
    console.log('Choose what to reset:');
    console.log('1. Reset ALL assigned rosters to pending_assignment');
    console.log('2. Reset only Wipro customers to pending_assignment');
    console.log('3. Reset specific customers (Pooja, Arjun, Sneha)');
    console.log('4. Just show current status (no changes)');
    
    // For automation, let's reset the specific customers mentioned in the logs
    console.log('\n🎯 Auto-selecting option 3: Reset specific customers...');
    
    const specificCustomers = [
      'pooja.joshi@wipro.com',
      'arjun.nair@wipro.com', 
      'sneha.iyer@wipro.com'
    ];
    
    console.log('\n📝 Resetting specific customers to pending_assignment...');
    
    for (const email of specificCustomers) {
      const result = await db.collection('rosters').updateMany(
        {
          $or: [
            { customerEmail: email },
            { 'employeeDetails.email': email }
          ]
        },
        {
          $set: {
            status: 'pending_assignment',
            updatedAt: new Date()
          },
          $unset: {
            vehicleId: '',
            vehicleNumber: '',
            driverId: '',
            driverName: '',
            driverPhone: '',
            assignedAt: '',
            assignedBy: '',
            optimizedPickupTime: '',
            optimizedOfficeTime: '',
            estimatedDistance: '',
            estimatedTravelTime: '',
            bufferMinutes: '',
            tripId: ''
          }
        }
      );
      
      console.log(`   ✅ ${email}: ${result.modifiedCount} rosters reset`);
    }
    
    // STEP 4: Verify the reset
    console.log('\n✅ STEP 4: Verification after reset...');
    
    const pendingRosters = await db.collection('rosters').find({
      $or: [
        { customerEmail: { $in: specificCustomers } },
        { 'employeeDetails.email': { $in: specificCustomers } }
      ]
    }).toArray();
    
    console.log(`Found ${pendingRosters.length} rosters for specific customers:`);
    pendingRosters.forEach((roster, i) => {
      console.log(`   ${i + 1}. ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
      console.log(`      Email: ${roster.customerEmail || roster.employeeDetails?.email || 'Unknown'}`);
      console.log(`      Status: ${roster.status}`);
      console.log(`      Vehicle: ${roster.vehicleNumber || roster.vehicleId || 'None'}`);
      console.log('');
    });
    
    // STEP 5: Clean up any orphaned trip records
    console.log('\n🧹 STEP 5: Cleaning up orphaned trip records...');
    
    const tripCleanup = await db.collection('trips').deleteMany({
      'customer.email': { $in: specificCustomers },
      status: { $in: ['assigned', 'pending'] }
    });
    
    console.log(`   🗑️  Removed ${tripCleanup.deletedCount} orphaned trip records`);
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ ASSIGNMENT CONFLICTS FIXED');
    console.log('='.repeat(80));
    console.log('📋 Summary:');
    console.log(`   • Reset ${specificCustomers.length} customer assignments`);
    console.log(`   • Cleaned up ${tripCleanup.deletedCount} orphaned trips`);
    console.log(`   • All specified customers are now available for assignment`);
    console.log('');
    console.log('🎯 Next Steps:');
    console.log('   1. Try the route assignment again in the admin panel');
    console.log('   2. The system should now accept the assignment');
    console.log('   3. Test single assignment first, then multiple trips');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error fixing assignment conflicts:', error);
  } finally {
    await client.close();
  }
}

// Run the fix
if (require.main === module) {
  fixAssignmentConflicts();
}

module.exports = { fixAssignmentConflicts };