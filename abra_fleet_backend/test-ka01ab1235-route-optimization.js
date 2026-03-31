// Test that vehicle KA01AB1235 will now be selected for route optimization
// This simulates what the frontend route optimization service does

const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testRouteOptimization() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const vehiclesCollection = db.collection('vehicles');
    const driversCollection = db.collection('drivers');
    
    console.log('\n' + '='.repeat(80));
    console.log('TESTING ROUTE OPTIMIZATION FOR VEHICLE KA01AB1235');
    console.log('='.repeat(80));
    
    // Step 1: Fetch vehicle (simulating what the API does)
    console.log('\n📍 STEP 1: Fetching vehicle KA01AB1235...');
    const vehicle = await vehiclesCollection.findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle not found');
      return;
    }
    
    console.log('✅ Vehicle found:');
    console.log(`   - Registration: ${vehicle.registrationNumber}`);
    console.log(`   - Status: ${vehicle.status}`);
    console.log(`   - Seat Capacity: ${vehicle.seatCapacity || vehicle.seatingCapacity}`);
    console.log(`   - Assigned Driver (raw):`, vehicle.assignedDriver);
    
    // Step 2: Populate driver (simulating what the API does)
    console.log('\n📍 STEP 2: Populating driver details...');
    let populatedDriver = null;
    
    if (vehicle.assignedDriver) {
      const driverId = vehicle.assignedDriver._id || vehicle.assignedDriver;
      populatedDriver = await driversCollection.findOne({ _id: driverId });
      
      if (populatedDriver) {
        console.log('✅ Driver populated:');
        console.log(`   - Driver ID: ${populatedDriver.driverId}`);
        console.log(`   - Name: ${populatedDriver.personalInfo?.name}`);
        console.log(`   - Email: ${populatedDriver.contactInfo?.email || populatedDriver.personalInfo?.email}`);
        console.log(`   - Status: ${populatedDriver.status}`);
      }
    }
    
    // Step 3: Format vehicle data as API would return it
    console.log('\n📍 STEP 3: Formatting vehicle data as API returns...');
    const apiVehicle = {
      _id: vehicle._id,
      registrationNumber: vehicle.registrationNumber,
      name: vehicle.name || vehicle.registrationNumber,
      status: vehicle.status,
      seatCapacity: vehicle.seatCapacity || vehicle.seatingCapacity || 4,
      assignedDriver: populatedDriver ? {
        _id: populatedDriver._id,
        driverId: populatedDriver.driverId,
        name: populatedDriver.personalInfo?.name || 'Unknown',
        email: populatedDriver.contactInfo?.email || populatedDriver.personalInfo?.email || '',
        phone: populatedDriver.contactInfo?.phone || populatedDriver.personalInfo?.phone || '',
        status: populatedDriver.status
      } : null,
      assignedCustomers: vehicle.assignedCustomers || [],
      currentLocation: vehicle.currentLocation || {
        coordinates: [77.5946, 12.9716], // Default Bangalore
        latitude: 12.9716,
        longitude: 77.5946
      }
    };
    
    console.log('✅ API formatted vehicle:');
    console.log(JSON.stringify(apiVehicle, null, 2));
    
    // Step 4: Run frontend validation checks
    console.log('\n📍 STEP 4: Running frontend validation checks...');
    console.log('-'.repeat(80));
    
    // Check 1: Status
    const statusCheck = apiVehicle.status?.toUpperCase() === 'ACTIVE';
    console.log(`✓ Status check: ${statusCheck ? '✅ PASS' : '❌ FAIL'} (${apiVehicle.status})`);
    
    // Check 2: Capacity
    const capacity = apiVehicle.seatCapacity || 4;
    console.log(`✓ Capacity: ${capacity} seats`);
    
    // Check 3: Driver assignment (THIS IS THE CRITICAL CHECK)
    let hasDriver = false;
    let driverInfo = 'None';
    
    if (apiVehicle.assignedDriver) {
      const driver = apiVehicle.assignedDriver;
      hasDriver = driver.driverId != null || driver.name != null;
      driverInfo = driver.name || driver.driverId || 'Unknown';
    }
    
    console.log(`✓ Driver check: ${hasDriver ? '✅ PASS' : '❌ FAIL'} (${driverInfo})`);
    
    // Check 4: Available seats
    const assigned = (apiVehicle.assignedCustomers || []).length;
    const driverSeats = hasDriver ? 1 : 0;
    const available = capacity - driverSeats - assigned;
    
    console.log(`✓ Assigned customers: ${assigned}`);
    console.log(`✓ Driver seats: ${driverSeats}`);
    console.log(`✓ Available seats: ${available}`);
    
    // Check 5: Can accommodate N customers?
    const testCustomerCounts = [1, 3, 5, 10, 15, 19];
    console.log('\n✓ Can accommodate:');
    for (const count of testCustomerCounts) {
      const canAccommodate = available >= count;
      console.log(`   - ${count} customers: ${canAccommodate ? '✅ YES' : '❌ NO'}`);
    }
    
    // Final verdict
    console.log('\n' + '='.repeat(80));
    console.log('FINAL VERDICT');
    console.log('='.repeat(80));
    
    const allChecksPassed = statusCheck && hasDriver && available > 0;
    
    if (allChecksPassed) {
      console.log('✅ VEHICLE WILL BE SELECTED FOR ROUTE OPTIMIZATION');
      console.log(`   - Status: ACTIVE ✓`);
      console.log(`   - Driver: ${driverInfo} ✓`);
      console.log(`   - Available seats: ${available} ✓`);
      console.log('\n🎉 SUCCESS! Vehicle KA01AB1235 is now ready for route optimization!');
    } else {
      console.log('❌ VEHICLE WILL BE REJECTED');
      if (!statusCheck) console.log('   - Status is not ACTIVE');
      if (!hasDriver) console.log('   - No driver assigned');
      if (available <= 0) console.log('   - No available seats');
    }
    
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ MongoDB connection closed');
  }
}

testRouteOptimization();
