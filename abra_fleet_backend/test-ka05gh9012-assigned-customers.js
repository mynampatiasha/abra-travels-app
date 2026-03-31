const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

async function testAssignedCustomers() {
  try {
    console.log('🔍 Testing KA05GH9012 assigned customers API...\n');
    
    // First, get the vehicle ID
    const vehiclesResponse = await axios.get(`${BASE_URL}/api/admin/vehicles`, {
      params: { search: 'KA05GH9012' }
    });
    
    if (!vehiclesResponse.data.success || vehiclesResponse.data.data.length === 0) {
      console.log('❌ Vehicle KA05GH9012 not found');
      return;
    }
    
    const vehicle = vehiclesResponse.data.data[0];
    console.log('✅ Vehicle found:');
    console.log('   ID:', vehicle._id);
    console.log('   Registration:', vehicle.registrationNumber);
    console.log('   Seat Capacity:', vehicle.seatingCapacity);
    console.log('   Capacity Object:', vehicle.capacity);
    console.log('   Assigned Customers Count:', vehicle.assignedCustomersCount);
    console.log('');
    
    // Now get assigned customers
    const assignedResponse = await axios.get(
      `${BASE_URL}/api/admin/vehicles/${vehicle._id}/assigned-customers`
    );
    
    console.log('📋 Assigned Customers API Response:');
    console.log(JSON.stringify(assignedResponse.data, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error.response?.data || error.message);
  }
}

testAssignedCustomers();
