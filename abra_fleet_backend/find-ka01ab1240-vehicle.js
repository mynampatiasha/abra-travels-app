// Find vehicle KA01AB1240 AND its driver that was assigned to the 3 Infosys employees
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function findVehicleAndDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 Searching for vehicle KA01AB1240...\n');
    
    // Search in vehicles collection
    const vehicle = await db.collection('vehicles').findOne({ vehicleNumber: 'KA01AB1240' });
    
    if (vehicle) {
      console.log('✅ VEHICLE FOUND:');
      console.log(`   Vehicle Number: ${vehicle.vehicleNumber}`);
      console.log(`   Organization: ${vehicle.organization || 'N/A'}`);
      console.log(`   Driver ID: ${vehicle.driverId || 'N/A'}`);
      console.log(`   Capacity: ${vehicle.capacity || 'N/A'}`);
      console.log(`   Vehicle ID: ${vehicle._id}`);
      
      // Now find the driver
      if (vehicle.driverId) {
        console.log('\n🔍 Searching for driver...\n');
        
        const driver = await db.collection('drivers').findOne({ driverId: vehicle.driverId });
        
        if (driver) {
          console.log('✅ DRIVER FOUND:');
          console.log(`   Driver Name: ${driver.name}`);
          console.log(`   Driver ID: ${driver.driverId}`);
          console.log(`   Phone: ${driver.phone || 'N/A'}`);
          console.log(`   Email: ${driver.email || 'N/A'}`);
          console.log(`   Organization: ${driver.organization || 'N/A'}`);
          
          console.log('\n📝 RESTORATION DATA:');
          console.log('   Use this data to restore the 3 Infosys rosters:');
          console.log(`   - Vehicle: ${vehicle.vehicleNumber}`);
          console.log(`   - Vehicle ID: ${vehicle._id}`);
          console.log(`   - Driver: ${driver.name}`);
          console.log(`   - Driver ID: ${driver.driverId}`);
          console.log(`   - Driver Phone: ${driver.phone || 'N/A'}`);
        } else {
          console.log('❌ DRIVER NOT FOUND');
          console.log(`   Looking for driverId: ${vehicle.driverId}`);
        }
      } else {
        console.log('\n⚠️  No driver assigned to this vehicle');
      }
      
    } else {
      console.log('❌ VEHICLE NOT FOUND in vehicles collection');
      
      // Check all vehicles to see what exists
      console.log('\n📊 All vehicles in database:\n');
      const allVehicles = await db.collection('vehicles').find({}).limit(10).toArray();
      allVehicles.forEach((v, i) => {
        console.log(`${i + 1}. ${v.vehicleNumber} - Org: ${v.organization || 'N/A'} - Driver: ${v.driverId || 'N/A'}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

findVehicleAndDriver();
