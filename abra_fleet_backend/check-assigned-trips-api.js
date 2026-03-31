// Check what the assigned-trips API returns
const axios = require('axios');

async function checkAssignedTrips() {
  try {
    console.log('🔍 Checking assigned trips API...\n');
    
    const response = await axios.get('http://localhost:3000/api/roster/admin/assigned-trips');
    
    console.log(`📊 Status: ${response.status}`);
    console.log(`📊 Total trips: ${response.data.data?.length || 0}\n`);
    
    if (response.data.data && response.data.data.length > 0) {
      console.log('📋 Trips found:');
      response.data.data.forEach((trip, index) => {
        console.log(`\n${index + 1}. Trip ID: ${trip._id || trip.id}`);
        console.log(`   Customer: ${trip.customerName} (${trip.customerEmail})`);
        console.log(`   Vehicle: ${trip.vehicleNumber}`);
        console.log(`   Driver: ${trip.driverName || 'N/A'}`);
        console.log(`   Status: ${trip.status}`);
      });
    } else {
      console.log('✅ No trips found');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    if (error.response) {
      console.error('Response:', error.response.data);
    }
  }
}

checkAssignedTrips();
