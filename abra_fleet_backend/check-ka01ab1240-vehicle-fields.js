// Check exact field structure of KA01AB1240 vehicle
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function checkVehicleFields() {
  const client = new MongoClient(MONGODB_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('abra_fleet');

    // Try different ways to find the vehicle
    console.log('🔍 Searching for KA01AB1240...\n');

    // Method 1: By vehicleNumber
    let vehicle = await db.collection('vehicles').findOne({
      vehicleNumber: 'KA01AB1240'
    });
    console.log('Method 1 - vehicleNumber:', vehicle ? '✅ Found' : '❌ Not found');

    // Method 2: By registrationNumber
    vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA01AB1240'
    });
    console.log('Method 2 - registrationNumber:', vehicle ? '✅ Found' : '❌ Not found');

    // Method 3: Case insensitive search
    vehicle = await db.collection('vehicles').findOne({
      $or: [
        { vehicleNumber: /KA01AB1240/i },
        { registrationNumber: /KA01AB1240/i }
      ]
    });
    console.log('Method 3 - case insensitive:', vehicle ? '✅ Found' : '❌ Not found');

    if (vehicle) {
      console.log('\n📋 VEHICLE STRUCTURE:');
      console.log('='.repeat(80));
      console.log(JSON.stringify(vehicle, null, 2));
    } else {
      console.log('\n❌ Vehicle not found with any method');
      console.log('\n📋 ALL VEHICLES:');
      const allVehicles = await db.collection('vehicles').find({}).toArray();
      allVehicles.forEach(v => {
        console.log(`\nVehicle ID: ${v._id}`);
        console.log(`  vehicleNumber: ${v.vehicleNumber}`);
        console.log(`  registrationNumber: ${v.registrationNumber}`);
        console.log(`  model: ${v.model}`);
      });
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkVehicleFields();
