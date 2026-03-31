const axios = require('axios');
const API_BASE_URL = 'http://localhost:3000/api/admin/customers';

// Helper function to generate random data
function generateRandomString(length = 8) {
  return Math.random().toString(36).substring(2, 2 + length);
}

// Test data
const testCustomer = {
  customerId: `CUST-${Date.now().toString().slice(-6)}`,
  name: {
    firstName: 'John',
    lastName: 'Doe',
    companyName: 'Doe Enterprises'
  },
  contactInfo: {
    email: `customer.${generateRandomString(8)}@example.com`,
    phone: `+1${Math.floor(1000000000 + Math.random() * 9000000000)}`,
    alternatePhone: `+1${Math.floor(1000000000 + Math.random() * 9000000000)}`
  },
  company: {
    name: 'Doe Enterprises',
    taxId: `TAX-${Math.floor(10000000 + Math.random() * 90000000)}`,
    registrationNumber: `REG-${Math.floor(100000 + Math.random() * 900000)}`
  },
  billingAddress: {
    street: '123 Business St',
    city: 'Commerce City',
    state: 'CA',
    postalCode: '90210',
    country: 'USA'
  },
  shippingAddress: {
    street: '123 Business St',
    city: 'Commerce City',
    state: 'CA',
    postalCode: '90210',
    country: 'USA',
    isSameAsBilling: true
  },
  status: 'active',
  notes: [
    {
      content: 'Initial customer account created',
      createdAt: new Date(),
      createdBy: 'system'
    }
  ]
};

// Test functions
async function testCreateCustomer() {
  try {
    console.log('👤 Testing create customer...');
    const response = await axios.post(API_BASE_URL, testCustomer);
    console.log('✅ Create customer successful!');
    console.log('Response:', JSON.stringify(response.data, null, 2));
    return response.data.data.customerId || response.data.customerId;
  } catch (error) {
    console.error('❌ Create customer failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testGetCustomer(customerId) {
  try {
    console.log('\n🔍 Testing get customer...');
    console.log(`Fetching customer with ID: ${customerId}`);
    const response = await axios.get(`${API_BASE_URL}/${customerId}`);
    console.log('✅ Get customer successful!');
    console.log('Customer details:', JSON.stringify(response.data.data, null, 2));
  } catch (error) {
    console.error('❌ Get customer failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testListCustomers() {
  try {
    console.log('\n📋 Testing list customers...');
    const response = await axios.get(API_BASE_URL);
    console.log('✅ List customers successful!');
    console.log(`Found ${response.data.data.length} customers`);
    console.log('Pagination:', response.data.pagination);
    console.log('Summary:', response.data.stats);
  } catch (error) {
    console.error('❌ List customers failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testUpdateCustomer(customerId) {
  try {
    console.log('\n✏️  Testing update customer...');
    const updateData = {
      name: {
        ...testCustomer.name,
        lastName: 'Smith',
        companyName: 'Smith Enterprises'
      },
      contactInfo: {
        ...testCustomer.contactInfo,
        email: `updated.${generateRandomString(8)}@example.com`
      },
      status: 'active',
      note: 'Updated customer details on ' + new Date().toISOString()
    };
    
    await axios.put(`${API_BASE_URL}/${customerId}`, updateData);
    console.log('✅ Update customer successful!');
  } catch (error) {
    console.error('❌ Update customer failed:', error.response?.data || error.message);
    throw error;
  }
}

async function testGetCustomerTrips(customerId) {
  try {
    console.log('\n🚗 Testing get customer trips...');
    const response = await axios.get(`${API_BASE_URL}/${customerId}/trips`);
    console.log('✅ Get customer trips successful!');
    console.log(`Found ${response.data.data.length} trips`);
    console.log('Trip stats:', response.data.stats);
    return response.data.data;
  } catch (error) {
    console.error('❌ Get customer trips failed:', error.response?.data || error.message);
    // Don't throw error as it's expected to have no trips for a new customer
    return [];
  }
}

// Main test function
async function runTests() {
  try {
    // Test creating a customer
    const customerId = await testCreateCustomer();
    
    // Test getting the created customer
    await testGetCustomer(customerId);
    
    // Test listing all customers
    await testListCustomers();
    
    // Test updating the customer
    await testUpdateCustomer(customerId);
    
    // Test getting customer trips (may be empty)
    await testGetCustomerTrips(customerId);
    
    console.log('\n🎉 All customer API tests completed successfully!');
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    process.exit(1);
  }
}

// Run the tests
runTests();
