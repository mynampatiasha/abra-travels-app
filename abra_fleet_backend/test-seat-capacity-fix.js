const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

async function testSeatCapacityFix() {
  console.log('\n🧪 Testing Seat Capacity Fix\n');
  console.log('=' .repeat(60));
  
  try {
    // Test 1: Get all vehicles and check capacity display
    console.log('\n📋 Test 1: Vehicle List Capacity');
    console.log('-'.repeat(60));
    
    const vehiclesResponse = await axios.get(`${BASE_URL}/api/admin/vehicles`, {
      params: { limit: 10 }
    });
    
    if (vehiclesResponse.data.success) {
      const vehicles = vehiclesResponse.data.data;
      console.log(`✅ Found ${vehicles.length} vehicles\n`);
      
      vehicles.forEach((vehicle, index) => {
        const registration = vehicle.registrationNumber || vehicle.vehicleNumber;
        const capacity = vehicle.seatCapacity || 'Unknown';
        const assigned = vehicle.assignedCustomers?.length || 0;
        const available = capacity !== 'Unknown' ? capacity - 1 - assigned : 'Unknown';
        
        console.log(`${index + 1}. ${registration}`);
        console.log(`   Total Seats: ${capacity}`);
        console.log(`   Assigned: ${assigned} customers`);
        console.log(`   Available: ${available} seats`);
        console.log('');
      });
    }
    
    // Test 2: Get assigned customers for KA01AB1234
    console.log('\n📋 Test 2: KA01AB1234 Assigned Customers');
    console.log('-'.repeat(60));
    
    // First find the vehicle ID
    const ka01Vehicle = vehiclesResponse.data.data.find(v => 
      v.registrationNumber === 'KA01AB1234' || 
      v.vehicleNumber === 'KA01AB1234'
    );
    
    if (ka01Vehicle) {
      console.log(`✅ Found vehicle: ${ka01Vehicle.registrationNumber}`);
      console.log(`   MongoDB ID: ${ka01Vehicle._id || ka01Vehicle.id}`);
      
      const vehicleId = ka01Vehicle._id || ka01Vehicle.id;
      const assignedResponse = await axios.get(
        `${BASE_URL}/api/admin/vehicles/${vehicleId}/assigned-customers`
      );
      
      if (assignedResponse.data.success) {
        const data = assignedResponse.data.data;
        const capacity = data.capacity;
        
        console.log('\n🎯 CAPACITY DETAILS:');
        console.log(`   Total Seats: ${capacity.total}`);
        console.log(`   Occupied: ${capacity.occupied}`);
        console.log(`   Available: ${capacity.available}`);
        console.log(`   Percentage: ${capacity.percentage}%`);
        console.log('\n   Breakdown:');
        console.log(`   - Driver: ${capacity.breakdown.driver}`);
        console.log(`   - Customers: ${capacity.breakdown.customers}`);
        
        console.log('\n👥 ASSIGNED CUSTOMERS:');
        data.customers.forEach((customer, index) => {
          console.log(`   ${index + 1}. ${customer.customerName}`);
          console.log(`      Organization: ${customer.organization}`);
          console.log(`      Type: ${customer.rosterType}`);
        });
        
        // Verify the fix
        console.log('\n✅ VERIFICATION:');
        if (capacity.total === 0) {
          console.log('   ❌ FAILED: Total seats is 0 (bug still exists)');
          console.log('   Expected: Total seats should be 40');
        } else if (capacity.total === 40) {
          console.log('   ✅ PASSED: Total seats is 40 (correct!)');
          console.log(`   ✅ Display format: ${capacity.occupied}/${capacity.total} seats`);
          console.log(`   ✅ Available seats: ${capacity.available} (should be 36 for 3 customers + 1 driver)`);
        } else {
          console.log(`   ⚠️  WARNING: Total seats is ${capacity.total} (expected 40)`);
        }
      }
    } else {
      console.log('❌ Vehicle KA01AB1234 not found');
    }
    
    // Test 3: Check other vehicles
    console.log('\n📋 Test 3: Other Vehicles Capacity Check');
    console.log('-'.repeat(60));
    
    for (const vehicle of vehiclesResponse.data.data.slice(0, 5)) {
      const vehicleId = vehicle._id || vehicle.id;
      const registration = vehicle.registrationNumber || vehicle.vehicleNumber;
      
      try {
        const response = await axios.get(
          `${BASE_URL}/api/admin/vehicles/${vehicleId}/assigned-customers`
        );
        
        if (response.data.success) {
          const capacity = response.data.data.capacity;
          const status = capacity.total > 0 ? '✅' : '❌';
          console.log(`${status} ${registration}: ${capacity.occupied}/${capacity.total} seats (${capacity.available} available)`);
        }
      } catch (error) {
        console.log(`⚠️  ${registration}: Error fetching data`);
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ Test completed successfully!');
    console.log('='.repeat(60) + '\n');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    if (error.response) {
      console.error('Response:', error.response.data);
    }
    console.log('\n💡 Make sure the backend server is running on port 3000');
  }
}

// Run the test
testSeatCapacityFix();
