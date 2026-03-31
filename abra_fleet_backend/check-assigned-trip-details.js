// Check assigned trip details to see why vehicle/driver not showing
const axios = require('axios');

async function checkAssignedTrips() {
  try {
    console.log('🔍 Checking assigned trips from API...\n');
    
    // You need to replace this with a valid admin token
    // Get it from your browser's localStorage or network tab
    const token = 'YOUR_ADMIN_TOKEN_HERE';
    
    const response = await axios.get('http://localhost:5000/api/roster/admin/assigned-trips', {
      headers: {
        'Authorization': `Bearer ${token}`
      },
      params: {
        status: 'assigned'
      }
    });
    
    console.log(`✅ Found ${response.data.count} assigned trips\n`);
    
    // Check first 5 trips
    const trips = response.data.data.slice(0, 5);
    
    trips.forEach((trip, idx) => {
      console.log(`\n${'='.repeat(60)}`);
      console.log(`Trip ${idx + 1}: ${trip.customerName}`);
      console.log(`${'='.repeat(60)}`);
      console.log(`📋 ID: ${trip.readableId}`);
      console.log(`👤 Customer: ${trip.customerName}`);
      console.log(`📧 Email: ${trip.customerEmail}`);
      console.log(`🏢 Company: ${trip.companyName}`);
      console.log(`📍 Status: ${trip.status}`);
      console.log(`\n🚗 VEHICLE INFO:`);
      console.log(`   Vehicle ID: ${trip.vehicleId || '❌ NOT SET'}`);
      console.log(`   Vehicle Number: ${trip.vehicleNumber || '❌ NOT SET'}`);
      console.log(`\n👨‍✈️ DRIVER INFO:`);
      console.log(`   Driver ID: ${trip.driverId || '❌ NOT SET'}`);
      console.log(`   Driver Name: ${trip.driverName || '❌ NOT SET'}`);
      console.log(`\n📅 DATES:`);
      console.log(`   Start: ${trip.startDate}`);
      console.log(`   End: ${trip.endDate}`);
      console.log(`   Assigned At: ${trip.assignedAt}`);
    });
    
    // Summary
    const withVehicle = trips.filter(t => t.vehicleId || t.vehicleNumber).length;
    const withDriver = trips.filter(t => t.driverId || t.driverName).length;
    const withBoth = trips.filter(t => (t.vehicleId || t.vehicleNumber) && (t.driverId || t.driverName)).length;
    
    console.log(`\n\n${'='.repeat(60)}`);
    console.log('📊 SUMMARY');
    console.log(`${'='.repeat(60)}`);
    console.log(`Total trips checked: ${trips.length}`);
    console.log(`With vehicle data: ${withVehicle}`);
    console.log(`With driver data: ${withDriver}`);
    console.log(`With both: ${withBoth}`);
    
    if (withBoth === 0) {
      console.log(`\n⚠️  PROBLEM FOUND!`);
      console.log(`None of the assigned trips have vehicle/driver data.`);
      console.log(`\n💡 SOLUTION:`);
      console.log(`These trips need to be assigned through Route Optimization.`);
      console.log(`The status is "assigned" but vehicle/driver fields are empty.`);
    }
    
  } catch (error) {
    if (error.response) {
      console.error('❌ API Error:', error.response.status, error.response.data);
    } else {
      console.error('❌ Error:', error.message);
    }
    
    console.log('\n💡 TIP: Make sure to:');
    console.log('1. Replace YOUR_ADMIN_TOKEN_HERE with actual token');
    console.log('2. Backend is running on port 5000');
    console.log('3. You are logged in as admin');
  }
}

checkAssignedTrips();
