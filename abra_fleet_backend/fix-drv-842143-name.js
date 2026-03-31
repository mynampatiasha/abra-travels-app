// Fix driver DRV-842143 to have proper name "John Doe"
// This ensures the driver shows correctly in both Driver Management and Route Optimization

const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixDriverName() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const driversCollection = db.collection('drivers');
    
    console.log('\n' + '='.repeat(80));
    console.log('FIXING DRIVER DRV-842143 NAME');
    console.log('='.repeat(80));
    
    // Step 1: Find driver
    console.log('\n📍 STEP 1: Finding driver DRV-842143...');
    const driver = await driversCollection.findOne({
      driverId: 'DRV-842143'
    });
    
    if (!driver) {
      console.log('❌ Driver not found');
      return;
    }
    
    console.log('✅ Driver found:');
    console.log(`   - _id: ${driver._id}`);
    console.log(`   - driverId: ${driver.driverId}`);
    console.log(`   - Current personalInfo:`, driver.personalInfo);
    console.log(`   - Current contactInfo:`, driver.contactInfo);
    
    // Step 2: Update driver with proper name
    console.log('\n📍 STEP 2: Updating driver with name "John Doe"...');
    
    const updateResult = await driversCollection.updateOne(
      { _id: driver._id },
      {
        $set: {
          'personalInfo.name': 'John Doe',
          'personalInfo.firstName': 'John',
          'personalInfo.lastName': 'Doe',
          'contactInfo.email': driver.contactInfo?.email || 'john.doe@abrafleet.com',
          'contactInfo.phone': driver.contactInfo?.phone || '+91 9876543210',
          updatedAt: new Date()
        }
      }
    );
    
    console.log('✅ Update result:');
    console.log(`   - Matched: ${updateResult.matchedCount}`);
    console.log(`   - Modified: ${updateResult.modifiedCount}`);
    
    // Step 3: Verify
    console.log('\n📍 STEP 3: Verifying update...');
    const updatedDriver = await driversCollection.findOne({
      driverId: 'DRV-842143'
    });
    
    console.log('✅ Updated driver:');
    console.log(`   - driverId: ${updatedDriver.driverId}`);
    console.log(`   - Name: ${updatedDriver.personalInfo?.name}`);
    console.log(`   - Email: ${updatedDriver.contactInfo?.email}`);
    console.log(`   - Phone: ${updatedDriver.contactInfo?.phone}`);
    
    // Step 4: Now update the vehicle reference
    console.log('\n📍 STEP 4: Updating vehicle KA01AB1235 with new driver info...');
    const vehiclesCollection = db.collection('vehicles');
    
    const vehicleUpdateResult = await vehiclesCollection.updateOne(
      { registrationNumber: 'KA01AB1235' },
      {
        $set: {
          'assignedDriver.name': 'John Doe',
          'assignedDriver.email': updatedDriver.contactInfo?.email || 'john.doe@abrafleet.com',
          'assignedDriver.phone': updatedDriver.contactInfo?.phone || '+91 9876543210',
          updatedAt: new Date()
        }
      }
    );
    
    console.log('✅ Vehicle update result:');
    console.log(`   - Matched: ${vehicleUpdateResult.matchedCount}`);
    console.log(`   - Modified: ${vehicleUpdateResult.modifiedCount}`);
    
    // Step 5: Final verification
    console.log('\n📍 STEP 5: Final verification...');
    const vehicle = await vehiclesCollection.findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    console.log('✅ Vehicle KA01AB1235:');
    console.log(`   - Registration: ${vehicle.registrationNumber}`);
    console.log(`   - Driver: ${vehicle.assignedDriver?.name}`);
    console.log(`   - Driver ID: ${vehicle.assignedDriver?.driverId}`);
    console.log(`   - Driver Email: ${vehicle.assignedDriver?.email}`);
    
    console.log('\n' + '='.repeat(80));
    console.log('FIX COMPLETE');
    console.log('='.repeat(80));
    console.log('\n✅ Driver DRV-842143 now has name "John Doe"');
    console.log('✅ Vehicle KA01AB1235 now shows driver as "John Doe"');
    console.log('\n💡 This matches what Driver Management UI shows!');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ MongoDB connection closed');
  }
}

fixDriverName();
