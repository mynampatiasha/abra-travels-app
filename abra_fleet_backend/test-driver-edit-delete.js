const axios = require('axios');
require('dotenv').config();

const BASE_URL = 'http://localhost:3000';

async function testDriverEditDelete() {
  console.log('\n🧪 Testing Driver Edit/Delete Functionality\n');
  console.log('='.repeat(60));
  
  try {
    // Test 1: Get all drivers
    console.log('\n1️⃣ Testing GET /api/admin/drivers');
    console.log('-'.repeat(60));
    
    const driversResponse = await axios.get(`${BASE_URL}/api/admin/drivers`, {
      params: { limit: 5 }
    });
    
    console.log(`✅ Status: ${driversResponse.status}`);
    console.log(`✅ Found ${driversResponse.data.data.length} drivers`);
    
    if (driversResponse.data.data.length === 0) {
      console.log('❌ No drivers found to test edit/delete');
      return;
    }
    
    const testDriver = driversResponse.data.data[0];
    console.log(`\n📋 Test Driver:`);
    console.log(`   ID: ${testDriver.driverId}`);
    console.log(`   Name: ${testDriver.name}`);
    console.log(`   Email: ${testDriver.email}`);
    console.log(`   Status: ${testDriver.status}`);
    
    // Test 2: Edit driver
    console.log('\n\n2️⃣ Testing PUT /api/admin/drivers/:id (Edit)');
    console.log('-'.repeat(60));
    
    const updateData = {
      name: testDriver.name + ' (Updated)',
      phone: testDriver.phone || '9999999999',
      status: testDriver.status
    };
    
    console.log(`Updating driver ${testDriver.driverId}...`);
    console.log(`Update data:`, updateData);
    
    try {
      const editResponse = await axios.put(
        `${BASE_URL}/api/admin/drivers/${testDriver.driverId}`,
        updateData
      );
      
      console.log(`✅ Status: ${editResponse.status}`);
      console.log(`✅ Edit successful!`);
      console.log(`   Updated name: ${editResponse.data.data.name}`);
      
      // Revert the change
      console.log(`\nReverting changes...`);
      await axios.put(
        `${BASE_URL}/api/admin/drivers/${testDriver.driverId}`,
        { name: testDriver.name }
      );
      console.log(`✅ Reverted successfully`);
      
    } catch (editError) {
      console.log(`❌ Edit failed: ${editError.response?.status || editError.message}`);
      console.log(`   Error: ${editError.response?.data?.message || editError.message}`);
    }
    
    // Test 3: Delete driver (soft delete)
    console.log('\n\n3️⃣ Testing DELETE /api/admin/drivers/:id (Delete)');
    console.log('-'.repeat(60));
    
    // Find an inactive driver or use the test driver
    const driverToDelete = driversResponse.data.data.find(d => d.status === 'inactive') || testDriver;
    
    console.log(`Attempting to delete driver ${driverToDelete.driverId}...`);
    console.log(`   Status: ${driverToDelete.status}`);
    
    try {
      const deleteResponse = await axios.delete(
        `${BASE_URL}/api/admin/drivers/${driverToDelete.driverId}`
      );
      
      console.log(`✅ Status: ${deleteResponse.status}`);
      console.log(`✅ Delete successful!`);
      console.log(`   Message: ${deleteResponse.data.message}`);
      
    } catch (deleteError) {
      if (deleteError.response?.status === 400) {
        console.log(`⚠️  Cannot delete: ${deleteError.response.data.message}`);
        console.log(`   This is expected for drivers with active assignments`);
      } else {
        console.log(`❌ Delete failed: ${deleteError.response?.status || deleteError.message}`);
        console.log(`   Error: ${deleteError.response?.data?.message || deleteError.message}`);
      }
    }
    
    // Summary
    console.log('\n\n' + '='.repeat(60));
    console.log('📊 TEST SUMMARY');
    console.log('='.repeat(60));
    console.log('✅ GET drivers: Working');
    console.log('✅ PUT (edit): Check results above');
    console.log('✅ DELETE: Check results above');
    console.log('\n💡 If edit/delete failed, check:');
    console.log('   1. Backend is running (node index.js)');
    console.log('   2. MongoDB connection is working');
    console.log('   3. Driver exists in MongoDB (not just Firebase)');
    console.log('   4. No active assignments for delete operation');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    if (error.code === 'ECONNREFUSED') {
      console.error('\n💡 Backend is not running!');
      console.error('   Start it with: cd abra_fleet_backend && node index.js');
    }
  }
}

testDriverEditDelete();
