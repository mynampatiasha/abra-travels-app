// Debug script to check the exact roster query conditions
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abrafleet';

async function debugRosterQuery() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db();
    
    console.log('\n🔍 DEBUGGING ROSTER ASSIGNMENT QUERY');
    console.log('='.repeat(60));
    
    // Get a sample pending roster
    const sampleRoster = await db.collection('rosters').findOne({
      status: { $in: ['pending_assignment', 'pending'] }
    });
    
    if (!sampleRoster) {
      console.log('❌ No pending rosters found');
      return;
    }
    
    console.log('📋 Sample Roster Found:');
    console.log(`   ID: ${sampleRoster._id}`);
    console.log(`   Customer: ${sampleRoster.customerName || 'Unknown'}`);
    console.log(`   Status: ${sampleRoster.status}`);
    console.log(`   VehicleId: ${sampleRoster.vehicleId || 'null'}`);
    console.log(`   DriverId: ${sampleRoster.driverId || 'null'}`);
    
    // Test the exact query from the assignment endpoint
    const rosterId = sampleRoster._id;
    
    console.log('\n🧪 Testing Assignment Query Conditions:');
    
    // Test 1: Basic ID match
    const basicMatch = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId)
    });
    console.log(`   ✅ Basic ID match: ${basicMatch ? 'FOUND' : 'NOT FOUND'}`);
    
    // Test 2: Status condition
    const statusMatch = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId),
      status: { $in: ['pending_assignment', 'pending'] }
    });
    console.log(`   ${statusMatch ? '✅' : '❌'} Status condition: ${statusMatch ? 'PASSED' : 'FAILED'}`);
    
    // Test 3: VehicleId condition
    const vehicleCondition = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId),
      $or: [
        { vehicleId: { $exists: false } },
        { vehicleId: null }
      ]
    });
    console.log(`   ${vehicleCondition ? '✅' : '❌'} VehicleId condition: ${vehicleCondition ? 'PASSED' : 'FAILED'}`);
    
    // Test 4: DriverId condition
    const driverCondition = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId),
      $and: [
        {
          $or: [
            { driverId: { $exists: false } },
            { driverId: null }
          ]
        }
      ]
    });
    console.log(`   ${driverCondition ? '✅' : '❌'} DriverId condition: ${driverCondition ? 'PASSED' : 'FAILED'}`);
    
    // Test 5: Complete query (as used in assignment)
    const completeQuery = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId),
      status: { $in: ['pending_assignment', 'pending'] },
      $or: [
        { vehicleId: { $exists: false } },
        { vehicleId: null }
      ],
      $and: [
        {
          $or: [
            { driverId: { $exists: false } },
            { driverId: null }
          ]
        }
      ]
    });
    console.log(`   ${completeQuery ? '✅' : '❌'} Complete query: ${completeQuery ? 'PASSED' : 'FAILED'}`);
    
    if (!completeQuery) {
      console.log('\n🔍 DETAILED FIELD ANALYSIS:');
      console.log(`   vehicleId field: ${JSON.stringify(sampleRoster.vehicleId)}`);
      console.log(`   vehicleId type: ${typeof sampleRoster.vehicleId}`);
      console.log(`   driverId field: ${JSON.stringify(sampleRoster.driverId)}`);
      console.log(`   driverId type: ${typeof sampleRoster.driverId}`);
      
      // Check if fields exist but have unexpected values
      if (sampleRoster.vehicleId !== null && sampleRoster.vehicleId !== undefined) {
        console.log(`   ⚠️  vehicleId is not null/undefined: ${sampleRoster.vehicleId}`);
      }
      if (sampleRoster.driverId !== null && sampleRoster.driverId !== undefined) {
        console.log(`   ⚠️  driverId is not null/undefined: ${sampleRoster.driverId}`);
      }
    }
    
    // Test with a simpler query
    console.log('\n🧪 Testing Simplified Query:');
    const simpleQuery = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId),
      status: { $in: ['pending_assignment', 'pending'] }
    });
    console.log(`   ${simpleQuery ? '✅' : '❌'} Simple query (ID + status only): ${simpleQuery ? 'PASSED' : 'FAILED'}`);
    
    console.log('\n💡 RECOMMENDATION:');
    if (completeQuery) {
      console.log('   ✅ Query should work - assignment should succeed');
    } else if (simpleQuery) {
      console.log('   ⚠️  Roster exists but has vehicleId/driverId already set');
      console.log('   💡 Try clearing these fields first or use a different query');
    } else {
      console.log('   ❌ Roster not found or wrong status');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

debugRosterQuery();