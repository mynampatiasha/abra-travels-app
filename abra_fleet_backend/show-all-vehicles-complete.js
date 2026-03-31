// Show ALL vehicles with complete details
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function showAllVehicles() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n📊 ALL VEHICLES IN DATABASE:\n');
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`Found ${vehicles.length} vehicles\n`);
    
    for (let i = 0; i < vehicles.length; i++) {
      const v = vehicles[i];
      console.log(`${i + 1}. Vehicle Details:`);
      console.log(`   Vehicle Number: ${v.vehicleNumber || 'MISSING'}`);
      console.log(`   Organization: ${v.organization || 'N/A'}`);
      console.log(`   Driver ID: ${v.driverId || 'N/A'}`);
      console.log(`   Capacity: ${v.capacity || 'N/A'}`);
      console.log(`   Type: ${v.type || 'N/A'}`);
      console.log(`   Status: ${v.status || 'N/A'}`);
      console.log(`   _id: ${v._id}`);
      console.log('');
    }
    
    // Check if there are any rosters that reference KA01AB1240
    console.log('\n🔍 Checking if any rosters still reference KA01AB1240...\n');
    
    const rostersWithVehicle = await db.collection('rosters')
      .find({ vehicleNumber: 'KA01AB1240' })
      .toArray();
    
    console.log(`Found ${rostersWithVehicle.length} rosters with vehicle KA01AB1240\n`);
    
    if (rostersWithVehicle.length > 0) {
      rostersWithVehicle.forEach((r, i) => {
        console.log(`${i + 1}. ${r.customerName} (${r.customerEmail})`);
        console.log(`   Status: ${r.status}`);
        console.log(`   Driver: ${r.driverName || 'N/A'}`);
        console.log('');
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

showAllVehicles();
