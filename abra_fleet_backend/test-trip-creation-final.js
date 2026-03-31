require('dotenv').config();
const admin = require('./config/firebase');
const http = require('http');

const ADMIN_UID = 'qnwp8d0clDSSNuSm3ugmXYLSI3K2'; // Admin Firebase UID

async function createCustomToken() {
  try {
    console.log('🔑 Creating Firebase custom token for admin...');
    const customToken = await admin.auth().createCustomToken(ADMIN_UID, {
      role: 'admin',
      email: 'admin@abrafleet.com'
    });
    console.log('✅ Custom token created');
    console.log('Token preview:', customToken.substring(0, 50) + '...');
    return customToken;
  } catch (error) {
    console.error('❌ Error creating custom token:', error);
    throw error;
  }
}

async function testTripCreation(token) {
  console.log('\n🧪 Testing trip creation with custom token...');
  
  const tripData = {
    vehicleId: "694a7cddc1882931f34d491f",
    startPoint: {
      latitude: 12.99618906536335,
      longitude: 77.58292702636719,
      address: "Test Pickup Location"
    },
    endPoint: {
      latitude: 12.992843757324497,
      longitude: 77.70308999023437,
      address: "Test Drop Location"
    },
    distance: 13.00,
    scheduledPickupTime: new Date(Date.now() + 30 * 60000).toISOString(),
    customerName: "Test Customer",
    customerEmail: "test@example.com",
    customerPhone: "+91 9876543210",
    tripType: "manual",
    notes: "Test trip with custom Firebase token"
  };

  const postData = JSON.stringify(tripData);

  const options = {
    hostname: 'localhost',
    port: 3001,
    path: '/api/trips/create',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData),
      'Authorization': `Bearer ${token}`
    }
  };

  return new Promise((resolve, reject) => {
    console.log('📡 Sending request to:', `http://localhost:3001/api/trips/create`);
    
    const req = http.request(options, (res) => {
      console.log('Status Code:', res.statusCode);
      
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        console.log('\n📄 Response Body:');
        try {
          const jsonData = JSON.parse(data);
          console.log(JSON.stringify(jsonData, null, 2));
          
          if (res.statusCode === 200 && jsonData.success) {
            console.log('\n🎉 SUCCESS! Trip created successfully!');
            console.log('🎫 Trip Number:', jsonData.data.tripNumber);
            console.log('👨‍✈️ Driver:', jsonData.data.driver.name);
            console.log('🚗 Vehicle:', jsonData.data.vehicle.number);
            console.log('📏 Distance:', jsonData.data.trip.distance, 'km');
            console.log('📱 Notifications sent to driver and admin');
            console.log('\n✅ The MongoDB client issue has been RESOLVED!');
            console.log('✅ Trip creation is working correctly!');
          } else if (res.statusCode === 500 && jsonData.message === 'Database connection error') {
            console.log('\n❌ STILL FAILING: MongoDB client issue persists');
            console.log('Error:', jsonData.error);
            console.log('\nThe req.mongoClient is still undefined in the route.');
          } else {
            console.log('\n⚠️  Request failed with status:', res.statusCode);
            console.log('Error:', jsonData.error || jsonData.message);
          }
          
          resolve(jsonData);
        } catch (e) {
          console.log('Raw response:', data);
          resolve({ error: 'Invalid JSON response' });
        }
      });
    });

    req.on('error', (e) => {
      console.error('❌ Request error:', e.message);
      console.error('Error code:', e.code);
      console.error('Error details:', e);
      reject(e);
    });

    req.write(postData);
    req.end();
  });
}

async function main() {
  try {
    console.log('🚀 FINAL TEST: Trip Creation with Fresh Firebase Token');
    console.log('='.repeat(60));
    
    // Step 1: Create custom token
    const customToken = await createCustomToken();
    
    // Step 2: Test trip creation
    await testTripCreation(customToken);
    
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
  }
}

main();