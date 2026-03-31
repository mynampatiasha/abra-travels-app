// Check if auto mode actually assigned customers to rosters
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkAutoModeAssignment() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Check the 3 customers that were just assigned
    const rosterIds = [
      '693fcc6fc3a6100b317028cf', // Amit Patel
      '693fcc6bc3a6100b317028ce', // Priya Sharma
      '693fcc67c3a6100b317028cd'  // Rajesh Kumar
    ];
    
    console.log('\n🔍 CHECKING ROSTER ASSIGNMENTS...');
    console.log('='*80);
    
    for (const rosterId of rosterIds) {
      const roster = await db.collection('rosters').findOne({
        _id: new ObjectId(rosterId)
      });
      
      if (roster) {
        console.log(`\n📋 Roster: ${roster.customerName || 'Unknown'}`);
        console.log(`   ID: ${rosterId}`);
        console.log(`   Status: ${roster.status}`);
        console.log(`   Vehicle ID: ${roster.vehicleId || 'NOT ASSIGNED'}`);
        console.log(`   Vehicle Number: ${roster.vehicleNumber || 'NOT ASSIGNED'}`);
        console.log(`   Driver ID: ${roster.driverId || 'NOT ASSIGNED'}`);
        console.log(`   Driver Name: ${roster.driverName || 'NOT ASSIGNED'}`);
        console.log(`   Assigned At: ${roster.assignedAt || 'NOT ASSIGNED'}`);
        console.log(`   Pickup Sequence: ${roster.pickupSequence || 'N/A'}`);
        console.log(`   Optimized Pickup Time: ${roster.optimizedPickupTime || 'N/A'}`);
        
        if (roster.status === 'assigned') {
          console.log('   ✅ SUCCESSFULLY ASSIGNED!');
        } else {
          console.log(`   ❌ NOT ASSIGNED (status: ${roster.status})`);
        }
      } else {
        console.log(`\n❌ Roster ${rosterId} NOT FOUND`);
      }
    }
    
    // Check vehicle's assignedCustomers array
    console.log('\n\n🚗 CHECKING VEHICLE ASSIGNMENT...');
    console.log('='*80);
    
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA01AB1240'
    });
    
    if (vehicle) {
      console.log(`\n🚗 Vehicle: ${vehicle.registrationNumber}`);
      console.log(`   ID: ${vehicle._id}`);
      console.log(`   Assigned Customers: ${vehicle.assignedCustomers?.length || 0}`);
      
      if (vehicle.assignedCustomers && vehicle.assignedCustomers.length > 0) {
        console.log('\n   📋 Assigned Customers:');
        vehicle.assignedCustomers.forEach((customer, idx) => {
          console.log(`      ${idx + 1}. ${customer.customerName || 'Unknown'}`);
          console.log(`         Roster ID: ${customer.rosterId}`);
          console.log(`         Sequence: ${customer.sequence}`);
          console.log(`         Pickup Time: ${customer.pickupTime}`);
          console.log(`         Assigned At: ${customer.assignedAt}`);
        });
      } else {
        console.log('   ❌ NO CUSTOMERS IN VEHICLE assignedCustomers ARRAY');
      }
    } else {
      console.log('❌ Vehicle KA01AB1240 NOT FOUND');
    }
    
    // Count all assigned rosters
    console.log('\n\n📊 OVERALL STATISTICS...');
    console.log('='*80);
    
    const totalAssigned = await db.collection('rosters').countDocuments({
      status: 'assigned'
    });
    
    const totalPending = await db.collection('rosters').countDocuments({
      status: { $in: ['pending_assignment', 'overdue', 'urgent'] }
    });
    
    console.log(`\n✅ Total Assigned Rosters: ${totalAssigned}`);
    console.log(`⏳ Total Pending Rosters: ${totalPending}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkAutoModeAssignment();
