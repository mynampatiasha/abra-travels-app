const { MongoClient, ObjectId } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const uri = process.env.MONGODB_URI;

if (!uri) {
  console.error('❌ MONGODB_URI not found in .env file');
  process.exit(1);
}

console.log('✅ MongoDB URI loaded from .env');
const client = new MongoClient(uri);

async function fixVehicleCapacity() {
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find the vehicle by registration number (try multiple field names)
    let vehicle = await db.collection('vehicles').findOne({
      vehicleNumber: 'KA05GH9012'
    });
    
    if (!vehicle) {
      vehicle = await db.collection('vehicles').findOne({
        registrationNumber: 'KA05GH9012'
      });
    }
    
    if (!vehicle) {
      console.log('❌ Vehicle KA05GH9012 not found');
      console.log('Searching all vehicles...');
      const allVehicles = await db.collection('vehicles').find({}).limit(5).toArray();
      console.log('Sample vehicles:', allVehicles.map(v => ({
        vehicleNumber: v.vehicleNumber,
        registrationNumber: v.registrationNumber,
        name: v.name
      })));
      return;
    }
    
    console.log('📋 Current Vehicle Data:');
    console.log('   Vehicle Number:', vehicle.vehicleNumber);
    console.log('   Name:', vehicle.name);
    console.log('   seatingCapacity:', vehicle.seatingCapacity);
    console.log('   capacity:', vehicle.capacity);
    console.log('   seatCapacity:', vehicle.seatCapacity);
    console.log('');
    
    // Fix: Set seatingCapacity to 3
    const result = await db.collection('vehicles').updateOne(
      { _id: vehicle._id },
      { 
        $set: { 
          seatingCapacity: 3,
          'capacity.passengers': 3
        } 
      }
    );
    
    console.log('✅ Updated vehicle capacity');
    console.log('   Modified count:', result.modifiedCount);
    
    // Verify the update
    const updatedVehicle = await db.collection('vehicles').findOne({
      _id: vehicle._id
    });
    
    console.log('\n📋 Updated Vehicle Data:');
    console.log('   seatingCapacity:', updatedVehicle.seatingCapacity);
    console.log('   capacity:', updatedVehicle.capacity);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixVehicleCapacity();
