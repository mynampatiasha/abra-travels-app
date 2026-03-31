// Test what the trips API is actually returning
const axios = require('axios');

async function testTripsAPI() {
  try {
    console.log('🔍 Testing /api/roster/admin/assigned-trips endpoint...\n');
    
    const response = await axios.get('http://localhost:3000/api/roster/admin/assigned-trips', {
      headers: {
        // You'll need to add a valid token here
        // For now, let's see if we can access it
      }
    });
    
    console.log(`📊 Status: ${response.status}`);
    console.log(`📦 Total trips: ${response.data.data?.length || 0}\n`);
    
    if (response.data.data && response.data.data.length > 0) {
      // Show first 3 trips
      const tripsToShow = response.data.data.slice(0, 3);
      
      tripsToShow.forEach((trip, index) => {
        console.log('='.repeat(80));
        console.log(`Trip ${index + 1}:`);
        console.log(`  Customer: ${trip.customerName || 'Unknown'}`);
        console.log(`  Email: ${trip.customerEmail || 'N/A'}`);
        console.log(`  Company: ${trip.companyName || 'Unknown'}`);
        console.log('');
        console.log(`  🚗 Vehicle Number: ${trip.vehicleNumber || '(EMPTY)'}`);
        console.log(`  👤 Driver Name: ${trip.driverName || '(EMPTY)'}`);
        console.log(`  📞 Driver Phone: ${trip.driverPhone || '(EMPTY)'}`);
        console.log(`  🏢 Status: ${trip.status || 'Unknown'}`);
        console.log('');
      });
      
      console.log('='.repeat(80));
      console.log('\n✅ API is returning data');
      
      // Check if driver info is missing
      const missingDriverInfo = response.data.data.filter(trip => 
        !trip.driverName || !trip.driverPhone
      );
      
      if (missingDriverInfo.length > 0) {
        console.log(`\n⚠️  WARNING: ${missingDriverInfo.length} trips are missing driver information`);
        console.log('   This means the rosters need to be reassigned to populate driver data.');
      } else {
        console.log('\n✅ All trips have driver information!');
      }
    } else {
      console.log('⚠️  No trips found');
    }
    
  } catch (error) {
    if (error.response) {
      console.error(`❌ API Error: ${error.response.status} - ${error.response.statusText}`);
      console.error(`   Message: ${error.response.data?.message || 'Unknown error'}`);
    } else if (error.code === 'ECONNREFUSED') {
      console.error('❌ Backend is not running!');
      console.error('   Start it with: node index.js');
    } else {
      console.error('❌ Error:', error.message);
    }
  }
}

testTripsAPI();
