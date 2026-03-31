const axios = require('axios');
const API_BASE_URL = 'http://localhost:3000/api/admin/drivers';

// Helper function to generate random data
function generateRandomString(length = 8) {
  return Math.random().toString(36).substring(2, 2 + length);
}

// Test data
const testDriver = {
  driverId: `DRV-${Date.now().toString().slice(-6)}`,
  personalInfo: {
    firstName: 'John',
    lastName: 'Doe',
    phone: `+1${Math.floor(1000000000 + Math.random() * 9000000000)}`,
    email: `driver.${generateRandomString(8)}@example.com`,
    dateOfBirth: '1990-01-01',
    bloodGroup: 'O+',
    gender: 'male'
  },
  license: {
    licenseNumber: `DL${Math.floor(1000000000 + Math.random() * 9000000000)}`,
    type: 'commercial',
    issueDate: '2020-01-01',
    expiryDate: '2030-01-01',
    issuingAuthority: 'DMV'
  },
  emergencyContact: {
    name: 'Jane Doe',
    relationship: 'Spouse',
    phone: '+14155551212'
  },
  address: {
    street: '123 Main St',
    city: 'Anytown',
    state: 'CA',
    postalCode: '12345',
    country: 'USA'
  },
  status: 'active'
};

// Test functions
async function testCreateDriver() {
  try {
    console.log('🚗 Testing create driver...');
    const response = await axios.post(API_BASE_URL, testDriver);
    console.log('✅ Create driver successful!');
    console.log('Response:', JSON.stringify(response.data, null, 2));
    // Return the driverId from the response data
    return response.data.data.driverId || response.data.driverId;
  } catch (error) {
    console.error('❌ Create driver failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testGetDriver(driverId) {
  try {
    console.log('\n🔍 Testing get driver...');
    console.log(`Fetching driver with ID: ${driverId}`);
    const response = await axios.get(`${API_BASE_URL}/${driverId}`);
    console.log('✅ Get driver successful!');
    console.log('Driver details:', JSON.stringify(response.data.data, null, 2));
  } catch (error) {
    console.error('❌ Get driver failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testListDrivers() {
  try {
    console.log('\n📋 Testing list drivers...');
    const response = await axios.get(API_BASE_URL);
    console.log('✅ List drivers successful!');
    console.log(`Found ${response.data.data.length} drivers`);
    console.log('Pagination:', response.data.pagination);
    console.log('Summary:', response.data.summary);
  } catch (error) {
    console.error('❌ List drivers failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testUpdateDriver(driverId) {
  try {
    console.log('\n✏️  Testing update driver...');
    const updateData = {
      personalInfo: {
        ...testDriver.personalInfo,
        lastName: 'Smith',
        phone: `+1${Math.floor(1000000000 + Math.random() * 9000000000)}`
      },
      status: 'on_leave'
    };
    
    await axios.put(`${API_BASE_URL}/${driverId}`, updateData);
    console.log('✅ Update driver successful!');
  } catch (error) {
    console.error('❌ Update driver failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testAssignVehicle(driverId, vehicleId) {
  try {
    console.log('\n🔗 Testing assign vehicle...');
    await axios.post(`${API_BASE_URL}/${driverId}/assign-vehicle`, { vehicleId });
    console.log('✅ Assign vehicle successful!');
  } catch (error) {
    console.error('❌ Assign vehicle failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testUnassignVehicle(driverId) {
  try {
    console.log('\n🚫 Testing unassign vehicle...');
    await axios.post(`${API_BASE_URL}/${driverId}/unassign-vehicle`);
    console.log('✅ Unassign vehicle successful!');
  } catch (error) {
    console.error('❌ Unassign vehicle failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testGetDriverTrips(driverId) {
  try {
    console.log('\n📅 Testing get driver trips...');
    const response = await axios.get(`${API_BASE_URL}/${driverId}/trips`);
    console.log('✅ Get driver trips successful!');
    console.log(`Found ${response.data.data.length} trips`);
    console.log('Trip stats:', response.data.stats);
  } catch (error) {
    console.error('❌ Get driver trips failed:', error.response?.data || error.message);
    throw error;
  }
}

// Main test function
async function runTests() {
  try {
    // Test creating a driver
    const driverId = await testCreateDriver();
    
    // Test getting the created driver
    await testGetDriver(driverId);
    
    // Test listing all drivers
    await testListDrivers();
    
    // Test updating the driver
    await testUpdateDriver(driverId);
    
    // Test assigning a vehicle (replace 'VH001' with an existing vehicle ID from your database)
    // await testAssignVehicle(driverId, 'VH001');
    
    // Test unassigning the vehicle
    // await testUnassignVehicle(driverId);
    
    // Test getting driver trips
    await testGetDriverTrips(driverId);
    
    console.log('\n🎉 All tests completed successfully!');
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    process.exit(1);
  }
}

// Run the tests
runTests();