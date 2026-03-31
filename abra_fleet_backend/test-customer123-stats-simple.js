const axios = require('axios');
const { MongoClient } = require('mongodb');

const BACKEND_URL = 'http://localhost:3000';
const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function testCustomerStatsDirectly() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('TESTING CUSTOMER123 STATS - DIRECT DATABASE CHECK');
    console.log('='.repeat(60));

    // Step 1: Connect to MongoDB and check data
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('✓ Connected to MongoDB');

    // Step 2: Check if customer123 data exists
    console.log('\n2. Checking customer123 data...');
    
    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Check trips
    const trips = await db.collection('trips').find({ customerId: customerUID }).toArray();
    console.log(`✓ Found ${trips.length} trips for customer123`);
    
    // Check rosters
    const rosters = await db.collection('rosters').find({ userId: customerUID }).toArray();
    console.log(`✓ Found ${rosters.length} rosters for customer123`);

    if (trips.length === 0 && rosters.length === 0) {
      console.log('\n❌ NO DATA FOUND FOR CUSTOMER123!');
      console.log('This explains why the stats screen is not updating.');
      console.log('\nLet me check what data actually exists...');
      
      // Check all trips
      const allTrips = await db.collection('trips').find({}).limit(5).toArray();
      console.log('\nSample trips in database:');
      allTrips.forEach((trip, index) => {
        console.log(`${index + 1}. Trip ID: ${trip.tripId}, Customer ID: ${trip.customerId}, Status: ${trip.status}`);
      });
      
      // Check all rosters
      const allRosters = await db.collection('rosters').find({}).limit(5).toArray();
      console.log('\nSample rosters in database:');
      allRosters.forEach((roster, index) => {
        console.log(`${index + 1}. Roster ID: ${roster.rosterId}, User ID: ${roster.userId}, Status: ${roster.status}`);
      });
      
      return;
    }

    // Step 3: Analyze the data
    console.log('\n3. Analyzing customer123 data...');
    
    if (trips.length > 0) {
      console.log('\nTrips breakdown:');
      const tripsByStatus = {};
      trips.forEach(trip => {
        const status = trip.status || 'unknown';
        tripsByStatus[status] = (tripsByStatus[status] || 0) + 1;
      });
      
      Object.entries(tripsByStatus).forEach(([status, count]) => {
        console.log(`  - ${status}: ${count}`);
      });
    }
    
    if (rosters.length > 0) {
      console.log('\nRosters breakdown:');
      const rostersByStatus = {};
      rosters.forEach(roster => {
        const status = roster.status || 'unknown';
        rostersByStatus[status] = (rostersByStatus[status] || 0) + 1;
      });
      
      Object.entries(rostersByStatus).forEach(([status, count]) => {
        console.log(`  - ${status}: ${count}`);
      });
    }

    // Step 4: Test backend endpoint (if backend is running)
    console.log('\n4. Testing backend endpoint...');
    
    try {
      const response = await axios.get(`${BACKEND_URL}/api/health`, { timeout: 5000 });
      console.log('✓ Backend is running');
      
      // Try to test the stats endpoint with a mock token
      console.log('\n5. Testing stats endpoint...');
      console.log('Note: This will likely fail due to authentication, but we can see the error');
      
      try {
        const statsResponse = await axios.get(
          `${BACKEND_URL}/api/customer/stats/dashboard`,
          {
            headers: {
              'Authorization': 'Bearer mock_token',
              'Content-Type': 'application/json'
            },
            timeout: 5000
          }
        );
        console.log('Stats response:', statsResponse.data);
      } catch (authError) {
        if (authError.response) {
          console.log('Expected auth error:', authError.response.status, authError.response.data);
        } else {
          console.log('Connection error:', authError.message);
        }
      }
      
    } catch (backendError) {
      console.log('❌ Backend is not running or not accessible');
      console.log('Error:', backendError.message);
    }

    console.log('\n' + '='.repeat(60));
    console.log('DIAGNOSIS COMPLETE');
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('ERROR DURING TESTING:');
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

testCustomerStatsDirectly();