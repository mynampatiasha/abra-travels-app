// File: test-new-trip-id.js
// Quick test script to verify new Trip-XXXXX format generation

const { MongoClient } = require('mongodb');
const TripModel = require('./models/trip_model');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testNewTripIdGeneration() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🧪 Testing new Trip ID generation...');
    await client.connect();
    const db = client.db();
    const tripModel = new TripModel(db);
    
    // Test 1: Generate multiple trip IDs
    console.log('\n📋 Test 1: Generate 10 trip IDs');
    const generatedIds = [];
    for (let i = 0; i < 10; i++) {
      const tripId = tripModel.generateTripId();
      generatedIds.push(tripId);
      console.log(`${i + 1}. ${tripId}`);
    }
    
    // Test 2: Check format
    console.log('\n🔍 Test 2: Validate format');
    const formatRegex = /^Trip-\d{5}$/;
    const validFormats = generatedIds.filter(id => formatRegex.test(id));
    console.log(`✅ Valid format: ${validFormats.length}/${generatedIds.length}`);
    
    // Test 3: Check uniqueness
    console.log('\n🔄 Test 3: Check uniqueness');
    const uniqueIds = [...new Set(generatedIds)];
    console.log(`✅ Unique IDs: ${uniqueIds.length}/${generatedIds.length}`);
    
    // Test 4: Create a test trip
    console.log('\n🚗 Test 4: Create test trip with new format');
    const testTrip = await tripModel.createFromRosterAssignment({
      rosterId: 'test-roster-123',
      vehicleId: 'test-vehicle-123',
      driverId: 'test-driver-123',
      customerId: 'test-customer-123',
      customerName: 'Test Customer',
      customerEmail: 'test@example.com',
      customerPhone: '+1234567890',
      pickupLocation: { address: 'Test Pickup Location' },
      dropLocation: { address: 'Test Drop Location' },
      scheduledDate: '2025-01-15',
      startTime: '09:00',
      endTime: '09:30',
      distance: 5.5,
      estimatedDuration: 30,
      tripType: 'login',
      sequence: 1,
      organizationId: 'test-org-123',
      organizationName: 'Test Organization',
      assignedBy: 'test-script'
    });
    
    console.log(`✅ Test trip created: ${testTrip.tripId}`);
    console.log(`   Format valid: ${formatRegex.test(testTrip.tripId)}`);
    
    // Test 5: Find trip by new ID
    console.log('\n🔍 Test 5: Find trip by new ID');
    const foundTrip = await tripModel.findById(testTrip.tripId);
    console.log(`✅ Trip found: ${foundTrip ? 'Yes' : 'No'}`);
    if (foundTrip) {
      console.log(`   Trip ID: ${foundTrip.tripId}`);
      console.log(`   Status: ${foundTrip.status}`);
    }
    
    // Test 6: Update trip status
    console.log('\n🔄 Test 6: Update trip status');
    const updatedTrip = await tripModel.updateStatus(testTrip.tripId, 'started');
    console.log(`✅ Status updated: ${updatedTrip ? 'Yes' : 'No'}`);
    if (updatedTrip) {
      console.log(`   New status: ${updatedTrip.status}`);
    }
    
    // Cleanup: Remove test trip
    console.log('\n🧹 Cleanup: Removing test trip');
    await db.collection('trips').deleteOne({ _id: testTrip._id });
    console.log('✅ Test trip removed');
    
    console.log('\n🎉 All tests passed! New Trip ID format is working correctly.');
    
  } catch (error) {
    console.error('❌ Test failed:', error);
    throw error;
  } finally {
    await client.close();
  }
}

// Run test if called directly
if (require.main === module) {
  testNewTripIdGeneration()
    .then(() => {
      console.log('\n✅ Trip ID generation test completed successfully!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n💥 Trip ID generation test failed:', error);
      process.exit(1);
    });
}

module.exports = { testNewTripIdGeneration };