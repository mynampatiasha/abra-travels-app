// Check vehicles collection in MongoDB (the CORRECT way based on the API)
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkVehiclesProper() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n📊 CHECKING VEHICLES COLLECTION (MongoDB):\n');
    
    // Get ALL vehicles from MongoDB
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`Found ${vehicles.length} vehicles in MongoDB\n`);
    
    if (vehicles.length === 0) {
      console.log('❌ NO VEHICLES FOUND IN MONGODB!');
      console.log('\nThis explains why:');
      console.log('   1. Vehicle KA01AB1240 cannot be found');
      console.log('   2. Roster assignments had vehicle data but vehicles collection is empty');
      console.log('   3. The rosters were showing vehicle numbers but the actual vehicle records are missing\n');
      return;
    }
    
    // Display all vehicles with full details
    vehicles.forEach((v, i) => {
      console.log(`${i + 1}. Vehicle Details:`);
      console.log(`   Vehicle Number: ${v.vehicleNumber || v.registrationNumber || 'MISSING'}`);
      console.log(`   Vehicle ID: ${v.vehicleId || 'N/A'}`);
      console.log(`   Organization: ${v.organization || 'N/A'}`);
      console.log(`   Driver ID: ${v.driverId || 'N/A'}`);
      console.log(`   Capacity: ${v.capacity?.passengers || v.seatCapacity || v.seatingCapacity || 'N/A'}`);
      console.log(`   Type: ${v.vehicleType || 'N/A'}`);
      console.log(`   Status: ${v.status || 'N/A'}`);
      console.log(`   Make/Model: ${v.makeModel || v.make + ' ' + v.model || 'N/A'}`);
      console.log(`   MongoDB _id: ${v._id}`);
      console.log('');
    });
    
    // Now check if KA01AB1240 exists with any variation
    console.log('\n🔍 Searching for KA01AB1240 specifically...\n');
    
    const ka01ab1240 = await db.collection('vehicles').findOne({
      $or: [
        { vehicleNumber: 'KA01AB1240' },
        { registrationNumber: 'KA01AB1240' },
        { vehicleId: 'KA01AB1240' }
      ]
    });
    
    if (ka01ab1240) {
      console.log('✅ FOUND KA01AB1240!');
      console.log(JSON.stringify(ka01ab1240, null, 2));
      
      // Get driver details if assigned
      if (ka01ab1240.driverId) {
        console.log('\n🔍 Getting driver details...\n');
        const driver = await db.collection('drivers').findOne({ driverId: ka01ab1240.driverId });
        if (driver) {
          console.log('✅ Driver Found:');
          console.log(`   Name: ${driver.name}`);
          console.log(`   Phone: ${driver.phone || 'N/A'}`);
          console.log(`   Driver ID: ${driver.driverId}`);
        }
      }
    } else {
      console.log('❌ KA01AB1240 NOT FOUND in vehicles collection');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkVehiclesProper();
