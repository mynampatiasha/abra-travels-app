// Fix KA01AB1235 vehicle to have correct driver from drivers collection
// This ensures route optimization sees the same data as Driver Management

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixVehicleDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const driversCollection = db.collection('drivers');
    const vehiclesCollection = db.collection('vehicles');
    
    console.log('\n' + '='.repeat(80));
    console.log('FIXING VEHICLE KA01AB1235 DRIVER ASSIGNMENT');
    console.log('='.repeat(80));
    
    // Step 1: Find driver DRV-842143 in drivers collection
    console.log('\n📍 STEP 1: Finding driver DRV-842143 in drivers collection...');
    const driver = await driversCollection.findOne({
      $or: [
        { driverId: 'DRV-842143' },
        { driverCode: 'DRV-842143' },
        { employeeId: 'DRV-842143' }
      ]
    });
    
    if (!driver) {
      console.log('❌ Driver DRV-842143 not found in drivers collection');
      return;
    }
    
    console.log('✅ Driver found:');
    console.log(`   - _id: ${driver._id}`);
    console.log(`   - driverId: ${driver.driverId}`);
    console.log(`   - Name: ${driver.personalInfo?.name || 'N/A'}`);
    console.log(`   - Email: ${driver.contactInfo?.email || 'N/A'}`);
    console.log(`   - Status: ${driver.status}`);
    
    // Step 2: Find vehicle KA01AB1235
    console.log('\n📍 STEP 2: Finding vehicle KA01AB1235...');
    const vehicle = await vehiclesCollection.findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle KA01AB1235 not found');
      return;
    }
    
    console.log('✅ Vehicle found:');
    console.log(`   - _id: ${vehicle._id}`);
    console.log(`   - Registration: ${vehicle.registrationNumber}`);
    console.log(`   - Current assignedDriver:`, vehicle.assignedDriver);
    
    // Step 3: Update vehicle with correct driver reference
    console.log('\n📍 STEP 3: Updating vehicle with correct driver reference...');
    
    // Create proper driver reference that matches what the API returns
    const driverReference = {
      _id: driver._id,
      driverId: driver.driverId,
      name: driver.personalInfo?.name || 'Unknown',
      email: driver.contactInfo?.email || '',
      phone: driver.contactInfo?.phone || '',
      status: driver.status || 'ACTIVE'
    };
    
    console.log('Driver reference to be stored:');
    console.log(JSON.stringify(driverReference, null, 2));
    
    const updateResult = await vehiclesCollection.updateOne(
      { _id: vehicle._id },
      {
        $set: {
          assignedDriver: driverReference,
          driverId: driver.driverId, // Also set top-level driverId for compatibility
          updatedAt: new Date()
        }
      }
    );
    
    console.log('\n✅ Update result:');
    console.log(`   - Matched: ${updateResult.matchedCount}`);
    console.log(`   - Modified: ${updateResult.modifiedCount}`);
    
    // Step 4: Verify the update
    console.log('\n📍 STEP 4: Verifying the update...');
    const updatedVehicle = await vehiclesCollection.findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    console.log('✅ Updated vehicle:');
    console.log(`   - Registration: ${updatedVehicle.registrationNumber}`);
    console.log(`   - assignedDriver:`, updatedVehicle.assignedDriver);
    console.log(`   - driverId: ${updatedVehicle.driverId}`);
    
    // Step 5: Test what the API would return
    console.log('\n📍 STEP 5: Simulating API response...');
    
    // This is what the GET /api/admin/vehicles endpoint does
    const populatedDriver = await driversCollection.findOne({
      _id: updatedVehicle.assignedDriver?._id || updatedVehicle.assignedDriver
    });
    
    if (populatedDriver) {
      const apiDriverFormat = {
        _id: populatedDriver._id,
        driverId: populatedDriver.driverId,
        name: populatedDriver.personalInfo?.name || 'Unknown',
        email: populatedDriver.contactInfo?.email || '',
        phone: populatedDriver.contactInfo?.phone || '',
        status: populatedDriver.status || 'ACTIVE'
      };
      
      console.log('✅ API would return driver as:');
      console.log(JSON.stringify(apiDriverFormat, null, 2));
      
      // Check if this passes the frontend validation
      const hasDriver = apiDriverFormat.driverId != null || apiDriverFormat.name != null;
      console.log(`\n✅ Frontend validation: hasDriver = ${hasDriver}`);
      
      if (hasDriver) {
        console.log('✅ Vehicle will now pass route optimization driver check!');
      } else {
        console.log('❌ Vehicle still won\'t pass driver check');
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('FIX COMPLETE');
    console.log('='.repeat(80));
    console.log('\n💡 Next steps:');
    console.log('   1. Restart the backend server (if running)');
    console.log('   2. Refresh the frontend');
    console.log('   3. Try route optimization again');
    console.log('   4. Vehicle KA01AB1235 should now be available');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ MongoDB connection closed');
  }
}

fixVehicleDriver();
