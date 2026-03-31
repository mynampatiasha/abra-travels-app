const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function verifyCustomer123Data() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('VERIFYING CUSTOMER123 DATA');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Get rosters
    console.log('\n2. Checking rosters...');
    const rosters = await db.collection('rosters').find({ userId: customerUID }).toArray();
    console.log(`Found ${rosters.length} rosters:`);
    
    rosters.forEach((roster, index) => {
      console.log(`  ${index + 1}. ${roster.rosterId}: ${roster.status}`);
      console.log(`     - Date range: ${new Date(roster.fromDate).toLocaleDateString()} to ${new Date(roster.toDate).toLocaleDateString()}`);
      console.log(`     - Vehicle: ${roster.vehicleNumber}, Driver: ${roster.driverName}`);
      console.log(`     - Trips: ${roster.totalTrips || 0} (${roster.completedTrips || 0} completed, ${roster.scheduledTrips || 0} scheduled)`);
    });

    // Get trips
    console.log('\n3. Checking trips...');
    const trips = await db.collection('trips').find({ customerId: customerUID }).toArray();
    console.log(`Found ${trips.length} trips:`);
    
    const tripStatusCounts = {
      completed: trips.filter(t => t.status === 'completed').length,
      ongoing: trips.filter(t => t.status === 'ongoing').length,
      scheduled: trips.filter(t => t.status === 'scheduled').length,
      cancelled: trips.filter(t => t.status === 'cancelled').length
    };

    console.log(`Trip status breakdown:`);
    console.log(`  - Completed: ${tripStatusCounts.completed}`);
    console.log(`  - Ongoing: ${tripStatusCounts.ongoing}`);
    console.log(`  - Scheduled: ${tripStatusCounts.scheduled}`);
    console.log(`  - Cancelled: ${tripStatusCounts.cancelled}`);
    console.log(`  - Total: ${trips.length}`);

    // Check trip dates to verify logic
    console.log('\n4. Checking trip date logic...');
    const today = new Date(2024, 11, 23); // December 23, 2024
    console.log(`Today's date: ${today.toLocaleDateString()}`);
    
    let logicalErrors = 0;
    trips.forEach(trip => {
      const tripDate = new Date(trip.scheduledDate);
      const expectedStatus = tripDate < today ? 'completed' : 
                           tripDate.toDateString() === today.toDateString() ? 'ongoing' : 'scheduled';
      
      if (trip.status !== expectedStatus) {
        console.log(`  ⚠️  Trip ${trip.tripId} on ${tripDate.toLocaleDateString()} has status '${trip.status}' but should be '${expectedStatus}'`);
        logicalErrors++;
      }
    });
    
    if (logicalErrors === 0) {
      console.log('✅ All trip statuses are logically correct!');
    } else {
      console.log(`❌ Found ${logicalErrors} logical errors in trip statuses`);
    }

    // Test the stats calculation function
    console.log('\n5. Testing stats calculation...');
    
    function calculateTripStats(trips = [], rosters = []) {
      const checkStatus = (item, statuses) => {
        if (!item.status || typeof item.status !== 'string') return false;
        return statuses.includes(item.status.trim().toLowerCase());
      };

      const completedTrips = trips.filter(t => checkStatus(t, ['completed', 'delivered'])).length;
      const ongoingTrips = trips.filter(t => checkStatus(t, ['in_progress', 'picked_up', 'ongoing'])).length;
      const scheduledTrips = trips.filter(t => checkStatus(t, ['scheduled', 'assigned'])).length;
      const cancelledTrips = trips.filter(t => checkStatus(t, ['cancelled'])).length;
      
      const pendingRosters = rosters.filter(r => checkStatus(r, ['pending_assignment', 'pending'])).length;
      const cancelledRosters = rosters.filter(r => checkStatus(r, ['cancelled'])).length;

      const completed = completedTrips;
      const ongoing = ongoingTrips + scheduledTrips + pendingRosters;
      const cancelled = cancelledTrips + cancelledRosters;
      const total = completed + ongoing + cancelled;

      return { 
        completed, 
        ongoing, 
        cancelled, 
        total,
        breakdown: {
          completedTrips,
          ongoingTrips,
          scheduledTrips,
          cancelledTrips,
          pendingRosters,
          cancelledRosters
        }
      };
    }
    
    const stats = calculateTripStats(trips, rosters);
    console.log('Calculated stats:', JSON.stringify(stats, null, 2));

    console.log('\n' + '='.repeat(60));
    console.log('✅ DATA VERIFICATION COMPLETE!');
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR VERIFYING DATA:');
    console.error('='.repeat(60));
    console.error(error.message);
    console.error(error.stack);
  } finally {
    if (client) {
      await client.close();
    }
    process.exit(0);
  }
}

verifyCustomer123Data();