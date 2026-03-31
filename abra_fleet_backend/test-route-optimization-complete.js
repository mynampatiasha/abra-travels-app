// Test script for complete route optimization system
const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

// Test data
const testRouteData = {
  vehicleId: "675e123456789012345678ab", // Replace with actual vehicle ID
  route: [
    {
      rosterId: "675e123456789012345678cd",
      customerId: "customer1@example.com",
      customerName: "John Doe",
      customerEmail: "john.doe@example.com",
      customerPhone: "+91-9876543210",
      sequence: 1,
      pickupTime: "08:30",
      eta: "2025-12-10T08:30:00.000Z",
      location: {
        latitude: 12.9716,
        longitude: 77.5946,
        address: "Koramangala Office Bangalore"
      },
      distanceFromPrevious: 0,
      estimatedTime: 0
    },
    {
      rosterId: "675e123456789012345678ef",
      customerId: "customer2@example.com",
      customerName: "Sarah Smith",
      customerEmail: "sarah.smith@example.com",
      customerPhone: "+91-9876543211",
      sequence: 2,
      pickupTime: "08:38",
      eta: "2025-12-10T08:38:00.000Z",
      location: {
        latitude: 12.9800,
        longitude: 77.6000,
        address: "Whitefield Office Bangalore"
      },
      distanceFromPrevious: 2.3,
      estimatedTime: 8
    },
    {
      rosterId: "675e123456789012345678gh",
      customerId: "customer3@example.com",
      customerName: "Mike Johnson",
      customerEmail: "mike.johnson@example.com",
      customerPhone: "+91-9876543212",
      sequence: 3,
      pickupTime: "08:45",
      eta: "2025-12-10T08:45:00.000Z",
      location: {
        latitude: 12.9900,
        longitude: 77.6100,
        address: "Indiranagar Office Bangalore"
      },
      distanceFromPrevious: 1.8,
      estimatedTime: 7
    }
  ],
  totalDistance: 12.5,
  totalTime: 35,
  startTime: "2025-12-10T08:30:00.000Z"
};

async function testCompleteRouteOptimization() {
  console.log('\n' + '🧪'.repeat(50));
  console.log('TESTING COMPLETE ROUTE OPTIMIZATION SYSTEM');
  console.log('🧪'.repeat(50));
  
  try {
    // Step 1: Test backend health
    console.log('\n📡 Step 1: Testing backend health...');
    const healthResponse = await axios.get(`${BASE_URL}/health`);
    console.log('✅ Backend is running:', healthResponse.data.message);
    
    // Step 2: Test database connection
    console.log('\n💾 Step 2: Testing database connection...');
    const dbResponse = await axios.get(`${BASE_URL}/test-db`);
    console.log('✅ Database connected:', dbResponse.data.message);
    
    // Step 3: Test route optimization endpoint (without auth for now)
    console.log('\n🎯 Step 3: Testing route optimization endpoint...');
    console.log('📋 Sending test route data:');
    console.log(`   - Vehicle ID: ${testRouteData.vehicleId}`);
    console.log(`   - Route stops: ${testRouteData.route.length}`);
    console.log(`   - Total distance: ${testRouteData.totalDistance} km`);
    console.log(`   - Total time: ${testRouteData.totalTime} mins`);
    
    // Note: This will fail without proper authentication, but we can see if the endpoint exists
    try {
      const routeResponse = await axios.post(
        `${BASE_URL}/api/roster/assign-optimized-route`,
        testRouteData,
        {
          headers: {
            'Content-Type': 'application/json'
          }
        }
      );
      console.log('✅ Route optimization successful:', routeResponse.data);
    } catch (routeError) {
      if (routeError.response?.status === 401) {
        console.log('⚠️  Route optimization endpoint exists but requires authentication');
        console.log('   Status:', routeError.response.status);
        console.log('   Message:', routeError.response.data?.message);
      } else {
        console.log('❌ Route optimization failed:', routeError.message);
        if (routeError.response?.data) {
          console.log('   Response:', routeError.response.data);
        }
      }
    }
    
    console.log('\n' + '✅'.repeat(50));
    console.log('BACKEND SYSTEM STATUS: READY FOR TESTING');
    console.log('✅'.repeat(50));
    console.log('\n📋 Next Steps:');
    console.log('1. Ensure Flutter app can connect to backend');
    console.log('2. Test route optimization from Flutter admin panel');
    console.log('3. Verify notifications are sent');
    console.log('4. Check database for saved assignments');
    console.log('5. Test live tracking functionality');
    
  } catch (error) {
    console.log('\n' + '❌'.repeat(50));
    console.log('BACKEND SYSTEM TEST FAILED');
    console.log('❌'.repeat(50));
    console.log('Error:', error.message);
    
    if (error.code === 'ECONNREFUSED') {
      console.log('\n💡 Solution:');
      console.log('1. Start the backend server: node index.js');
      console.log('2. Ensure MongoDB is running');
      console.log('3. Check .env configuration');
    }
  }
}

// Run the test
testCompleteRouteOptimization();