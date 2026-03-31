// Debug maintenance issue - check vehicle lookup
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DATABASE_NAME = 'abra_fleet';

async function debugMaintenanceIssue() {
  console.log('🔧 ========== DEBUGGING MAINTENANCE ISSUE ==========');
  
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DATABASE_NAME);
    
    // Check what vehicle ID is being sent from frontend
    const vehicleIdFromFrontend = 'KAB009367';
    console.log('\n🔍 Searching for vehicle with ID:', vehicleIdFromFrontend);
    
    // Try different search methods
    console.log('\n1️⃣ Searching by exact vehicleId...');
    let vehicle = await db.collection('vehicles').findOne({ vehicleId: vehicleIdFromFrontend });
    if (vehicle) {
      console.log('✅ Found by vehicleId:', vehicle.registrationNumber || vehicle.vehicleNumber);
    } else {
      console.log('❌ Not found by vehicleId');
    }
    
    console.log('\n2️⃣ Searching by registrationNumber...');
    vehicle = await db.collection('vehicles').findOne({ registrationNumber: vehicleIdFromFrontend });
    if (vehicle) {
      console.log('✅ Found by registrationNumber:', vehicle.registrationNumber);
    } else {
      console.log('❌ Not found by registrationNumber');
    }
    
    console.log('\n3️⃣ Searching by vehicleNumber...');
    vehicle = await db.collection('vehicles').findOne({ vehicleNumber: vehicleIdFromFrontend });
    if (vehicle) {
      console.log('✅ Found by vehicleNumber:', vehicle.vehicleNumber);
    } else {
      console.log('❌ Not found by vehicleNumber');
    }
    
    console.log('\n4️⃣ Searching with case-insensitive regex...');
    vehicle = await db.collection('vehicles').findOne({ 
      $or: [
        { vehicleId: { $regex: new RegExp(vehicleIdFromFrontend, 'i') } },
        { registrationNumber: { $regex: new RegExp(vehicleIdFromFrontend, 'i') } },
        { vehicleNumber: { $regex: new RegExp(vehicleIdFromFrontend, 'i') } }
      ]
    });
    if (vehicle) {
      console.log('✅ Found with case-insensitive search:', vehicle.registrationNumber || vehicle.vehicleNumber);
    } else {
      console.log('❌ Not found with case-insensitive search');
    }
    
    // List all vehicles to see what's available
    console.log('\n5️⃣ Listing all vehicles in database...');
    const allVehicles = await db.collection('vehicles').find({}).limit(10).toArray();
    console.log(`Found ${allVehicles.length} vehicles:`);
    
    allVehicles.forEach((v, index) => {
      console.log(`${index + 1}. ID: ${v._id}`);
      console.log(`   vehicleId: ${v.vehicleId || 'N/A'}`);
      console.log(`   registrationNumber: ${v.registrationNumber || 'N/A'}`);
      console.log(`   vehicleNumber: ${v.vehicleNumber || 'N/A'}`);
      console.log(`   make: ${v.make || 'N/A'} ${v.model || ''}`);
      console.log('');
    });
    
    // Check if the vehicle ID exists in any field
    console.log('\n6️⃣ Checking if KAB009367 exists anywhere...');
    const searchResult = await db.collection('vehicles').findOne({
      $or: [
        { vehicleId: 'KAB009367' },
        { registrationNumber: 'KAB009367' },
        { vehicleNumber: 'KAB009367' },
        { 'name': 'KAB009367' }
      ]
    });
    
    if (searchResult) {
      console.log('✅ Found vehicle with KAB009367:', JSON.stringify(searchResult, null, 2));
    } else {
      console.log('❌ KAB009367 not found in any vehicle field');
      console.log('💡 This explains why the maintenance report creation is failing');
    }
    
    console.log('\n🎯 ========== DEBUG COMPLETE ==========');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('🔌 MongoDB connection closed');
  }
}

// Run the debug
debugMaintenanceIssue();