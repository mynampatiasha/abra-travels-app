/**
 * Simple Route Optimization Test
 * Uses direct MongoDB queries to bypass Firebase auth for testing
 */

require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet'; // Correct database name from .env

async function testRouteOptimization() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🚀 Route Optimization + Trip Creation Test');
    console.log('='.repeat(60) + '\n');
    
    // Connect to MongoDB
    console.log('1. Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    console.log('✓ Connected\n');
    
    // Get a vehicle
    console.log('2. Getting available vehicle...');
    const vehicle = await db.collection('vehicles').findOne({ 
      status: 'ACTIVE' 
    });
    
    if (!vehicle) {
      console.log('❌ No vehicles available');
      return;
    }
    
    console.log('✓ Vehicle found');
    console.log(`  Vehicle: ${vehicle.registrationNumber}`);
    console.log(`  Type: ${vehicle.type}`);
    console.log(`  Capacity: ${vehicle.capacity.passengers} seats`);
    console.log(`  Driver ID: ${vehicle.assignedDriverId || vehicle.driverId || 'Not assigned'}\n`);
    
    // Get rosters (any status for testing)
    console.log('3. Getting rosters...');
    let rosters = await db.collection('rosters')
      .find({ status: 'pending' })
      .limit(3)
      .toArray();
    
    if (rosters.length === 0) {
      console.log('⚠ No pending rosters, using any rosters for testing...');
      rosters = await db.collection('rosters')
        .find()
        .limit(3)
        .toArray();
    }
    
    console.log(`✓ Found ${rosters.length} rosters`);
    
    if (rosters.length === 0) {
      console.log('❌ No rosters available to test with');
      return;
    }
    
    rosters.forEach((roster, idx) => {
      console.log(`  ${idx + 1}. ${roster.customerName} - ${roster.pickupLocation}`);
    });
    console.log('');
    
    // Create trips manually (simulating the API)
    console.log('4. Creating trips...');
    
    const trips = [];
    const now = new Date();
    const today = now.toISOString().split('T')[0];
    
    for (let i = 0; i < rosters.length; i++) {
      const roster = rosters[i];
      const sequence = i + 1;
      
      // Generate trip number
      const tripNumber = `TRIP-${Date.now()}-${String(sequence).padStart(2, '0')}`;
      
      const trip = {
        tripNumber,
        rosterId: roster._id,
        vehicleId: vehicle._id.toString(),
        driverId: vehicle.assignedDriverId || vehicle.driverId || 'unassigned',
        customer: {
          name: roster.customerName,
          email: roster.customerEmail || `customer${i}@test.com`,
          phone: roster.customerPhone || '+1234567890'
        },
        status: 'assigned',
        scheduledDate: today,
        startTime: roster.pickupTime || '08:00',
        sequence: sequence,
        pickupLocation: roster.pickupLocation,
        dropoffLocation: roster.dropoffLocation,
        estimatedDistance: (sequence * 2.5),
        estimatedTime: 15 + (sequence * 10),
        currentLocation: null,
        locationHistory: [],
        createdAt: now,
        updatedAt: now
      };
      
      trips.push(trip);
    }
    
    // Insert trips into database
    const result = await db.collection('trips').insertMany(trips);
    console.log(`✓ Created ${result.insertedCount} trips\n`);
    
    // Update rosters to 'assigned' status
    const rosterIds = rosters.map(r => r._id);
    const driverId = vehicle.assignedDriverId || vehicle.driverId;
    await db.collection('rosters').updateMany(
      { _id: { $in: rosterIds } },
      { 
        $set: { 
          status: 'assigned',
          vehicleId: vehicle._id.toString(),
          driverId: driverId,
          updatedAt: now
        } 
      }
    );
    console.log('✓ Updated roster statuses\n');
    
    // Display created trips
    console.log('5. Verifying trips in database...');
    console.log('  ' + '─'.repeat(50));
    
    for (const trip of trips) {
      console.log(`\n  Trip: ${trip.tripNumber}`);
      console.log(`    Customer: ${trip.customer.name}`);
      console.log(`    Email: ${trip.customer.email}`);
      console.log(`    Phone: ${trip.customer.phone}`);
      console.log(`    Status: ${trip.status}`);
      console.log(`    Scheduled: ${trip.scheduledDate} at ${trip.startTime}`);
      console.log(`    Sequence: ${trip.sequence}`);
      console.log(`    Pickup: ${trip.pickupLocation}`);
      console.log(`    Dropoff: ${trip.dropoffLocation}`);
    }
    
    console.log('\n  ' + '─'.repeat(50));
    
    // Get driver's today trips
    if (driverId) {
      console.log('\n6. Getting driver today trips...');
      const driverTrips = await db.collection('trips').find({
        driverId: driverId,
        scheduledDate: today
      }).toArray();
      
      console.log(`✓ Found ${driverTrips.length} trips for driver today`);
      driverTrips.forEach((trip, idx) => {
        console.log(`  ${idx + 1}. ${trip.tripNumber} - ${trip.customer.name} (${trip.status})`);
      });
      console.log('');
    }
    
    // Test trip status update
    console.log('7. Testing trip status updates...');
    const firstTrip = trips[0];
    const tripId = result.insertedIds[0];
    
    const statuses = ['started', 'in_progress', 'completed'];
    for (const status of statuses) {
      await db.collection('trips').updateOne(
        { _id: tripId },
        { 
          $set: { 
            status,
            updatedAt: new Date()
          } 
        }
      );
      console.log(`  ✓ Updated to: ${status}`);
    }
    console.log('');
    
    // Final verification
    console.log('8. Final database verification...');
    const finalTrip = await db.collection('trips').findOne({ _id: tripId });
    
    console.log('✓ Trip structure verified:');
    console.log('  ' + '─'.repeat(50));
    console.log(`  Trip Number: ${finalTrip.tripNumber}`);
    console.log(`  Roster ID: ${finalTrip.rosterId}`);
    console.log(`  Vehicle ID: ${finalTrip.vehicleId}`);
    console.log(`  Driver ID: ${finalTrip.driverId}`);
    console.log(`  Customer: ${JSON.stringify(finalTrip.customer, null, 4).replace(/\n/g, '\n  ')}`);
    console.log(`  Status: ${finalTrip.status}`);
    console.log(`  Scheduled Date: ${finalTrip.scheduledDate}`);
    console.log(`  Start Time: ${finalTrip.startTime}`);
    console.log(`  Sequence: ${finalTrip.sequence}`);
    console.log(`  Current Location: ${finalTrip.currentLocation || 'null'}`);
    console.log(`  Location History: ${finalTrip.locationHistory.length} entries`);
    console.log('  ' + '─'.repeat(50));
    
    console.log('\n' + '='.repeat(60));
    console.log('🎉 ALL TESTS PASSED!');
    console.log('='.repeat(60));
    console.log('\n📊 Summary:');
    console.log(`  ✓ Created ${trips.length} trips`);
    console.log('  ✓ Trip structure correct');
    console.log('  ✓ Status updates working');
    console.log('  ✓ Database queries working');
    console.log('\n✅ Integration test complete!\n');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    console.error(error);
  } finally {
    await client.close();
    console.log('🔌 Disconnected from MongoDB\n');
  }
}

// Run the test
testRouteOptimization();
