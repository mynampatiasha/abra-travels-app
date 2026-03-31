const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function testRosterStructure() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('TESTING ROSTER STRUCTURE FOR CUSTOMER123');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Check rosters structure
    console.log('\n2. Checking rosters structure...');
    const rosters = await db.collection('rosters').find({ userId: customerUID }).toArray();
    
    console.log(`Found ${rosters.length} rosters:`);
    rosters.forEach((roster, index) => {
      console.log(`\nRoster ${index + 1}:`);
      console.log(`  - ID: ${roster.rosterId || 'N/A'}`);
      console.log(`  - Status: ${roster.status || 'N/A'}`);
      console.log(`  - Date Range: ${JSON.stringify(roster.dateRange || {})}`);
      console.log(`  - Driver: ${roster.driverName || 'N/A'}`);
      console.log(`  - Vehicle: ${roster.vehicleNumber || 'N/A'}`);
      console.log(`  - Roster Type: ${roster.rosterType || 'N/A'}`);
    });

    // Check trips structure
    console.log('\n3. Checking trips structure...');
    const trips = await db.collection('trips').find({ customerId: customerUID }).limit(5).toArray();
    
    console.log(`Sample of ${trips.length} trips:`);
    trips.forEach((trip, index) => {
      console.log(`\nTrip ${index + 1}:`);
      console.log(`  - ID: ${trip.tripId || 'N/A'}`);
      console.log(`  - Status: ${trip.status || 'N/A'}`);
      console.log(`  - Date: ${trip.scheduledDate || 'N/A'}`);
      console.log(`  - Driver: ${trip.driverName || 'N/A'}`);
      console.log(`  - Vehicle: ${trip.vehicleNumber || 'N/A'}`);
      console.log(`  - Roster ID: ${trip.rosterId || 'N/A'}`);
    });

    console.log('\n' + '='.repeat(60));
    console.log('✅ ROSTER STRUCTURE TEST COMPLETE');
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR TESTING ROSTER STRUCTURE:');
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

testRosterStructure();