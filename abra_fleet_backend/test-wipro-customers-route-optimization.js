// test-wipro-customers-route-optimization.js
// Test route optimization and notifications for the 3 Wipro customers
const { MongoClient, ObjectId } = require('mongodb');
const axios = require('axios');
require('dotenv').config();

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000';

async function testWiproCustomersRouteOptimization() {
  console.log('\n' + '='.repeat(80));
  console.log('🧪 TESTING ROUTE OPTIMIZATION FOR WIPRO CUSTOMERS');
  console.log('='.repeat(80));
  
  let mongoClient;
  
  try {
    // Connect to MongoDB
    const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
    mongoClient = new MongoClient(mongoUri);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    console.log('✅ Connected to MongoDB\n');
    
    // ========== STEP 1: FIND WIPRO CUSTOMER ROSTERS ==========
    console.log('📋 STEP 1: Finding Wipro customer rosters...');
    console.log('-'.repeat(80));
    
    const wiproEmails = [
      'sneha.iyer@wipro.com',
      'arjun.nair@wipro.com',
      'pooja.joshi@wipro.com'
    ];
    
    const wiproRosters = await db.collection('rosters').find({
      customerEmail: { $in: wiproEmails },
      status: { $in: ['pending_assignment', 'assigned'] }
    }).toArray();
    
    console.log(`Found ${wiproRosters.length} rosters for Wipro customers:\n`);
    
    wiproRosters.forEach((roster, idx) => {
      console.log(`${idx + 1}. ${roster.customerName} (${roster.customerEmail})`);
      console.log(`   Roster ID: ${roster._id}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Office: ${roster.officeLocation}`);
      console.log(`   Type: ${roster.rosterType}`);
      console.log(`   Customer ID: ${roster.customerId || 'NOT LINKED'}`);
    });
    
    if (wiproRosters.length === 0) {
      console.log('\n⚠️  No rosters found for Wipro customers!');
      console.log('   Please import rosters first.');
      return;
    }
    
    // Check if customers have user accounts
    console.log('\n📋 Checking if customers have user accounts...');
    const users = await db.collection('users').find({
      email: { $in: wiproEmails }
    }).toArray();
    
    console.log(`\n✅ Found ${users.length} user accounts:`);
    users.forEach(user => {
      console.log(`   - ${user.name} (${user.email})`);
      console.log(`     Firebase UID: ${user.firebaseUid}`);
      console.log(`     Role: ${user.role}`);
    });
    
    if (users.length < 3) {
      console.log(`\n⚠️  Only ${users.length}/3 customers have accounts!`);
      console.log('   Run migration script first: node migrate-roster-customers-to-firebase.js');
      return;
    }
    
    // ========== STEP 2: FIND AVAILABLE VEHICLE ==========
    console.log('\n\n📋 STEP 2: Finding available vehicle with driver...');
    console.log('-'.repeat(80));
    
    const vehicles = await db.collection('vehicles').find({
      status: 'active',
      assignedDriver: { $exists: true, $ne: null }
    }).toArray();
    
    if (vehicles.length === 0) {
      console.log('❌ No vehicles with assigned drivers found!');
      return;
    }
    
    const vehicle = vehicles[0];
    console.log(`\n✅ Using vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
    console.log(`   Vehicle ID: ${vehicle._id}`);
    console.log(`   Driver: ${vehicle.assignedDriver}`);
    console.log(`   Capacity: ${vehicle.seatCapacity || 'Unknown'}`);
    
    // ========== STEP 3: PREPARE ROUTE DATA ==========
    console.log('\n\n📋 STEP 3: Preparing route optimization data...');
    console.log('-'.repeat(80));
    
    const route = wiproRosters.map((roster, idx) => {
      const user = users.find(u => u.email === roster.customerEmail);
      
      return {
        rosterId: roster._id.toString(),
        customerId: user?.firebaseUid || roster.customerId,
        customerName: roster.customerName,
        customerEmail: roster.customerEmail,
        customerPhone: user?.phone || '',
        sequence: idx + 1,
        pickupTime: roster.fromTime || '08:00',
        eta: new Date(Date.now() + (idx + 1) * 15 * 60000).toISOString(),
        location: roster.loginPickupAddress || roster.officeLocation,
        distanceFromPrevious: (idx + 1) * 5,
        estimatedTime: 15
      };
    });
    
    console.log('\n📊 Route Plan:');
    route.forEach(stop => {
      console.log(`   Stop ${stop.sequence}: ${stop.customerName}`);
      console.log(`      Pickup: ${stop.pickupTime}`);
      console.log(`      Location: ${stop.location}`);
    });
    
    // ========== STEP 4: CALL ROUTE ASSIGNMENT API ==========
    console.log('\n\n📋 STEP 4: Calling route assignment API...');
    console.log('-'.repeat(80));
    
    const assignmentData = {
      vehicleId: vehicle._id.toString(),
      route: route,
      totalDistance: route.length * 5,
      totalTime: route.length * 15,
      startTime: route[0].pickupTime
    };
    
    console.log('\n📤 Sending request to backend...');
    console.log(`   URL: ${BACKEND_URL}/api/roster/assign-optimized-route`);
    console.log(`   Vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
    console.log(`   Customers: ${route.length}`);
    
    try {
      // Note: This requires authentication token
      // For testing, you'll need to get a valid admin token first
      console.log('\n⚠️  NOTE: This requires admin authentication token');
      console.log('   To test via API, you need to:');
      console.log('   1. Log in as admin in the app');
      console.log('   2. Get the Firebase ID token');
      console.log('   3. Add it to the request headers');
      console.log('\n💡 RECOMMENDED: Use the Flutter app instead (Option 1)');
      
      // Uncomment this if you have a valid token:
      /*
      const response = await axios.post(
        `${BACKEND_URL}/api/roster/assign-optimized-route`,
        assignmentData,
        {
          headers: {
            'Authorization': `Bearer YOUR_ADMIN_TOKEN_HERE`,
            'Content-Type': 'application/json'
          }
        }
      );
      
      console.log('\n✅ Route assignment successful!');
      console.log(JSON.stringify(response.data, null, 2));
      */
      
    } catch (apiError) {
      console.error('\n❌ API call failed:', apiError.message);
      if (apiError.response) {
        console.error('   Response:', apiError.response.data);
      }
    }
    
    // ========== ALTERNATIVE: DIRECT DATABASE UPDATE (FOR TESTING) ==========
    console.log('\n\n📋 ALTERNATIVE: Direct database update (for testing)...');
    console.log('-'.repeat(80));
    console.log('⚠️  This bypasses the API and directly updates the database');
    console.log('   Notifications will NOT be sent this way!');
    console.log('   Use this only to verify the data structure.\n');
    
    const readline = require('readline').createInterface({
      input: process.stdin,
      output: process.stdout
    });
    
    readline.question('Do you want to update rosters directly in DB? (yes/no): ', async (answer) => {
      if (answer.toLowerCase() === 'yes') {
        console.log('\n📝 Updating rosters in database...');
        
        for (const stop of route) {
          const updateResult = await db.collection('rosters').updateOne(
            { _id: new ObjectId(stop.rosterId) },
            {
              $set: {
                vehicleId: vehicle._id.toString(),
                driverId: vehicle.assignedDriver.toString(),
                status: 'assigned',
                assignedAt: new Date(),
                pickupSequence: stop.sequence,
                optimizedPickupTime: stop.pickupTime,
                estimatedArrival: new Date(stop.eta),
                pickupLocation: stop.location,
                updatedAt: new Date()
              }
            }
          );
          
          console.log(`   ✅ Updated roster for ${stop.customerName}`);
        }
        
        console.log('\n✅ Database updated successfully!');
        console.log('⚠️  NOTE: Notifications were NOT sent (API not called)');
        console.log('   To test notifications, use the Flutter app.');
      } else {
        console.log('\n✅ Skipped database update');
      }
      
      readline.close();
      
      // ========== SUMMARY ==========
      console.log('\n\n' + '='.repeat(80));
      console.log('📊 TEST SUMMARY');
      console.log('='.repeat(80));
      
      console.log('\n✅ What We Found:');
      console.log(`   - Wipro rosters: ${wiproRosters.length}`);
      console.log(`   - User accounts: ${users.length}/3`);
      console.log(`   - Available vehicles: ${vehicles.length}`);
      
      console.log('\n💡 RECOMMENDED TESTING APPROACH:');
      console.log('   1. Open Flutter app as admin');
      console.log('   2. Go to: Admin → Pending Rosters');
      console.log('   3. Select the 3 Wipro customer rosters');
      console.log('   4. Click "Optimize Route"');
      console.log('   5. Select vehicle and assign');
      console.log('   6. Check notification count (should be 3!)');
      
      console.log('\n📋 Customer Login Credentials:');
      users.forEach(user => {
        console.log(`   - ${user.email}`);
        console.log(`     Password: Check migration logs for temp password`);
      });
      
      console.log('\n' + '='.repeat(80));
      console.log('✅ TEST COMPLETE');
      console.log('='.repeat(80) + '\n');
      
      if (mongoClient) {
        await mongoClient.close();
      }
      process.exit(0);
    });
    
  } catch (error) {
    console.error('\n❌ FATAL ERROR:', error);
    console.error(error.stack);
    
    if (mongoClient) {
      await mongoClient.close();
    }
    process.exit(1);
  }
}

// Run the test
testWiproCustomersRouteOptimization();
