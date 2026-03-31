const axios = require('axios');

async function testVehicleAPI() {
  try {
    console.log('Testing vehicle API response...\n');
    
    const response = await axios.get('http://localhost:3000/api/admin/vehicles?limit=1');
    
    if (response.data.success) {
      const vehicle = response.data.data[0];
      
      console.log('Vehicle ID:', vehicle.vehicleId);
      console.log('Registration:', vehicle.registrationNumber);
      console.log('\nAssigned Driver Field:');
      console.log(JSON.stringify(vehicle.assignedDriver, null, 2));
      
      console.log('\nOther Driver Fields:');
      console.log('assignedDriverName:', vehicle.assignedDriverName);
      console.log('assignedDriverId:', vehicle.assignedDriverId);
      console.log('assignedDriverEmail:', vehicle.assignedDriverEmail);
      
    } else {
      console.log('API returned error:', response.data);
    }
    
  } catch (error) {
    console.error('Error:', error.message);
    if (error.response) {
      console.error('Response:', error.response.data);
    }
  }
}

testVehicleAPI();
