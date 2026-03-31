const axios = require('axios'); // npm install axios

async function testAddVehicle() {
  try {
    // Generate a unique vehicle ID using timestamp
    const timestamp = Date.now();
    const newVehicle = {
      vehicleId: `VH${timestamp.toString().slice(-4)}`,
      registrationNumber: `KA-05-AB-${timestamp.toString().slice(-4)}`,
      make: "Hyundai",
      model: "H1",
      year: 2022,
      type: "van",
      capacity: {
        passengers: 12,
        cargo: "1200kg"
      }
    };

    const response = await axios.post(
      'http://localhost:3000/api/admin/vehicles',
      newVehicle
    );

    console.log('✅ Vehicle added successfully!');
    console.log('Response:', response.data);
  } catch (error) {
    console.error('❌ Failed to add vehicle:', error.response?.data || error.message);
  }
}

testAddVehicle();