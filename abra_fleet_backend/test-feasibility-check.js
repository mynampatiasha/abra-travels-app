// test-feasibility-check.js - Test vehicle feasibility check
// This script helps test the time-based vehicle sharing with feasibility validation

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testFeasibilityCheck() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find a vehicle with existing assignments
    console.log('\n📋 Finding vehicles with existing assignments...');
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`\nFound ${vehicles.length} vehicles:`);
    
    for (const vehicle of vehicles) {
      console.log(`\n🚗 Vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
      console.log(`   ID: ${vehicle._id}`);
      
      // Check for assigned rosters
      const assignedRosters = await db.collection('rosters').find({
        vehicleId: vehicle._id.toString(),
        status: 'assigned',
        assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
      }).toArray();
      
      if (assignedRosters.length > 0) {
        console.log(`   ✅ Has ${assignedRosters.length} assigned customers:`);
        
        assignedRosters.forEach((roster, idx) => {
          console.log(`      ${idx + 1}. ${roster.customerName || 'Unknown'}`);
          console.log(`         Organization: ${roster.organization || roster.organizationName || 'Unknown'}`);
          console.log(`         Login: ${roster.startTime || roster.officeTime || 'Unknown'}`);
          console.log(`         Logout: ${roster.endTime || roster.officeEndTime || 'Unknown'}`);
          console.log(`         Location: ${roster.officeLocation || 'Unknown'}`);
        });
        
        // Find the last trip
        const lastTrip = assignedRosters.reduce((latest, current) => {
          const parseTime = (timeStr) => {
            if (!timeStr) return null;
            const [hours, minutes] = timeStr.split(':').map(Number);
            const date = new Date();
            date.setHours(hours, minutes, 0, 0);
            return date;
          };
          
          const currentEndTime = parseTime(current.endTime || current.toTime || current.logoutTime);
          const latestEndTime = parseTime(latest.endTime || latest.toTime || latest.logoutTime);
          
          if (!currentEndTime) return latest;
          if (!latestEndTime) return current;
          
          return currentEndTime > latestEndTime ? current : latest;
        });
        
        console.log(`\n   📍 Vehicle Status:`);
        console.log(`      Free at: ${lastTrip.endTime || lastTrip.toTime || lastTrip.logoutTime || 'Unknown'}`);
        console.log(`      Location: ${lastTrip.officeLocation || lastTrip.dropLocation || 'Unknown'}`);
        console.log(`      Organization: ${lastTrip.organization || lastTrip.organizationName || 'Unknown'}`);
        
        console.log(`\n   ✅ This vehicle can be assigned to:`);
        console.log(`      - Same organization (${lastTrip.organization || 'Unknown'}) at any time`);
        console.log(`      - Different organizations if timing allows (feasibility check will validate)`);
        
      } else {
        console.log(`   ⚪ No assigned customers - available for any organization`);
      }
    }
    
    // Find pending rosters for testing
    console.log('\n\n📋 Finding pending rosters for testing...');
    const pendingRosters = await db.collection('rosters').find({
      status: 'pending_assignment'
    }).limit(10).toArray();
    
    if (pendingRosters.length > 0) {
      console.log(`\nFound ${pendingRosters.length} pending rosters:`);
      
      // Group by organization and time
      const byOrg = {};
      pendingRosters.forEach(roster => {
        const org = roster.organization || roster.organizationName || 'Unknown';
        if (!byOrg[org]) byOrg[org] = [];
        byOrg[org].push(roster);
      });
      
      for (const [org, rosters] of Object.entries(byOrg)) {
        console.log(`\n   🏢 ${org}: ${rosters.length} customers`);
        rosters.forEach((roster, idx) => {
          console.log(`      ${idx + 1}. ${roster.customerName || 'Unknown'}`);
          console.log(`         Login: ${roster.startTime || roster.officeTime || 'Unknown'}`);
          console.log(`         Location: ${roster.pickupLocation || roster.officeLocation || 'Unknown'}`);
        });
      }
      
      console.log('\n\n💡 Testing Suggestions:');
      console.log('   1. Try assigning vehicles to customers from SAME organization → Should work');
      console.log('   2. Try assigning vehicles to customers from DIFFERENT organizations:');
      console.log('      - If times are far apart (2+ hours) → Should work if feasible');
      console.log('      - If times are close (< 2 hours) → Should be blocked');
      console.log('   3. System will check if driver can travel between locations in time');
      console.log('   4. Watch console logs for detailed feasibility analysis');
      
    } else {
      console.log('   ⚪ No pending rosters found');
    }
    
    console.log('\n\n🎯 How to Test:');
    console.log('   1. Go to Flutter app → Admin → Pending Rosters');
    console.log('   2. Select customers from different organizations');
    console.log('   3. Click "Optimize Route"');
    console.log('   4. Try to assign to a vehicle that already has customers');
    console.log('   5. System will validate:');
    console.log('      ✓ Organization compatibility');
    console.log('      ✓ Time conflicts');
    console.log('      ✓ Travel feasibility (NEW!)');
    console.log('   6. Check backend console for detailed logs');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Disconnected from MongoDB');
  }
}

testFeasibilityCheck();
