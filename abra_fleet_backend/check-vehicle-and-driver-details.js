const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkVehicleAndDriverDetails() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Vehicle ID from the rosters
    const vehicleId = '68e9e9e00cc297dd3ab4bd95';
    const driverId = '693815916f67e02c30df26a6';
    
    console.log('🚗 Checking Vehicle Details:\n');
    console.log('='.repeat(80));
    
    const vehicle = await db.collection('vehicles').findOne({ _id: new ObjectId(vehicleId) });
    
    if (vehicle) {
      console.log(`\n✅ Vehicle Found:`);
      console.log(`   ID: ${vehicleId}`);
      console.log(`   Name: ${vehicle.name || 'N/A'}`);
      console.log(`   Vehicle Number: ${vehicle.vehicleNumber || 'N/A'}`);
      console.log(`   Registration Number: ${vehicle.registrationNumber || 'N/A'}`);
      console.log(`   Number Plate: ${vehicle.numberPlate || 'N/A'}`);
      console.log(`   Reg No: ${vehicle.regNo || 'N/A'}`);
      console.log(`   Type: ${vehicle.type || 'N/A'}`);
      console.log(`   Capacity: ${vehicle.seatCapacity || vehicle.capacity || 'N/A'}`);
      console.log(`\n   📋 Full vehicle object keys:`);
      console.log(`   ${Object.keys(vehicle).join(', ')}`);
    } else {
      console.log(`\n❌ Vehicle NOT FOUND with ID: ${vehicleId}`);
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n👨‍✈️ Checking Driver Details:\n');
    console.log('='.repeat(80));
    
    const driver = await db.collection('drivers').findOne({ _id: new ObjectId(driverId) });
    
    if (driver) {
      console.log(`\n✅ Driver Found:`);
      console.log(`   ID: ${driverId}`);
      console.log(`   Name: ${driver.name || 'N/A'}`);
      console.log(`   Phone: ${driver.phone || driver.phoneNumber || driver.mobile || 'N/A'}`);
      console.log(`   Email: ${driver.email || 'N/A'}`);
      console.log(`   Driver Code: ${driver.driverCode || driver.code || 'N/A'}`);
      console.log(`   License Number: ${driver.licenseNumber || 'N/A'}`);
      console.log(`\n   📋 Full driver object keys:`);
      console.log(`   ${Object.keys(driver).join(', ')}`);
    } else {
      console.log(`\n❌ Driver NOT FOUND with ID: ${driverId}`);
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n💡 DIAGNOSIS:');
    console.log('   The rosters have vehicleNumber="Unknown" and no driverPhone field.');
    console.log('   This means when the assignment happened, the backend did not properly');
    console.log('   extract the vehicle number and driver phone from the database.');
    console.log('\n   The fix needs to update the rosters with the correct vehicle number');
    console.log('   and driver phone from the actual vehicle and driver records.');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkVehicleAndDriverDetails();
