// Test script to check vehicle data structure and driver population
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function testVehicleDataStructure() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    console.log('\n' + '🚗'.repeat(50));
    console.log('TESTING VEHICLE DATA STRUCTURE');
    console.log('🚗'.repeat(50));
    
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Get all vehicles
    console.log('\n📋 Fetching all vehicles...');
    const vehicles = await db.collection('vehicles').find({}).limit(5).toArray();
    
    console.log(`✅ Found ${vehicles.length} vehicles`);
    
    for (let i = 0; i < vehicles.length; i++) {
      const vehicle = vehicles[i];
      console.log(`\n🚗 Vehicle ${i + 1}:`);
      console.log(`   - _id: ${vehicle._id}`);
      console.log(`   - vehicleId: ${vehicle.vehicleId}`);
      console.log(`   - name: ${vehicle.name}`);
      console.log(`   - vehicleNumber: ${vehicle.vehicleNumber}`);
      console.log(`   - registrationNumber: ${vehicle.registrationNumber}`);
      console.log(`   - makeModel: ${vehicle.makeModel}`);
      console.log(`   - seatCapacity: ${vehicle.seatCapacity}`);
      console.log(`   - seatingCapacity: ${vehicle.seatingCapacity}`);
      console.log(`   - status: ${vehicle.status}`);
      console.log(`   - assignedDriver: ${vehicle.assignedDriver}`);
      console.log(`   - assignedCustomers: ${vehicle.assignedCustomers?.length || 0} customers`);
      
      // Check if driver exists
      if (vehicle.assignedDriver) {
        console.log(`\n   🔍 Checking driver: ${vehicle.assignedDriver}`);
        
        // Try different driver collections/formats
        const driverInDrivers = await db.collection('drivers').findOne({
          driverId: vehicle.assignedDriver
        });
        
        const driverInUsers = await db.collection('users').findOne({
          $or: [
            { _id: vehicle.assignedDriver },
            { userId: vehicle.assignedDriver },
            { driverId: vehicle.assignedDriver },
            { email: vehicle.assignedDriver }
          ]
        });
        
        console.log(`   - Found in 'drivers' collection: ${driverInDrivers ? 'YES' : 'NO'}`);
        console.log(`   - Found in 'users' collection: ${driverInUsers ? 'YES' : 'NO'}`);
        
        if (driverInDrivers) {
          console.log(`   - Driver name: ${driverInDrivers.personalInfo?.firstName} ${driverInDrivers.personalInfo?.lastName}`);
          console.log(`   - Driver status: ${driverInDrivers.status}`);
        }
        
        if (driverInUsers) {
          console.log(`   - User name: ${driverInUsers.name}`);
          console.log(`   - User role: ${driverInUsers.role}`);
          console.log(`   - User status: ${driverInUsers.status}`);
        }
      } else {
        console.log(`   ⚠️  No driver assigned`);
      }
    }
    
    // Check collections
    console.log('\n📊 Collection Statistics:');
    const vehicleCount = await db.collection('vehicles').countDocuments();
    const driverCount = await db.collection('drivers').countDocuments();
    const userCount = await db.collection('users').countDocuments({ role: 'driver' });
    
    console.log(`   - Total vehicles: ${vehicleCount}`);
    console.log(`   - Total drivers (drivers collection): ${driverCount}`);
    console.log(`   - Total driver users (users collection): ${userCount}`);
    
    // Sample driver data structure
    console.log('\n👨‍✈️ Sample driver data structures:');
    
    const sampleDriver = await db.collection('drivers').findOne({});
    if (sampleDriver) {
      console.log('\n   From drivers collection:');
      console.log(`   - _id: ${sampleDriver._id}`);
      console.log(`   - driverId: ${sampleDriver.driverId}`);
      console.log(`   - personalInfo: ${JSON.stringify(sampleDriver.personalInfo, null, 6)}`);
      console.log(`   - status: ${sampleDriver.status}`);
    }
    
    const sampleDriverUser = await db.collection('users').findOne({ role: 'driver' });
    if (sampleDriverUser) {
      console.log('\n   From users collection (role: driver):');
      console.log(`   - _id: ${sampleDriverUser._id}`);
      console.log(`   - name: ${sampleDriverUser.name}`);
      console.log(`   - email: ${sampleDriverUser.email}`);
      console.log(`   - role: ${sampleDriverUser.role}`);
      console.log(`   - status: ${sampleDriverUser.status}`);
    }
    
    console.log('\n' + '✅'.repeat(50));
    console.log('VEHICLE DATA STRUCTURE TEST COMPLETED');
    console.log('✅'.repeat(50));
    
  } catch (error) {
    console.error('\n❌ Test failed:', error);
  } finally {
    await client.close();
  }
}

// Run the test
testVehicleDataStructure();