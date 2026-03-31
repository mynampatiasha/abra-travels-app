// show-ka01ab1235-exact-structure.js
// Show the EXACT database structure of vehicle KA01AB1235

const { MongoClient } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const dbName = 'abra_fleet';

async function showVehicleStructure() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle not found');
      return;
    }
    
    console.log('='.repeat(80));
    console.log('EXACT DATABASE STRUCTURE FOR KA01AB1235');
    console.log('='.repeat(80));
    console.log('\n📋 Complete Vehicle Document:\n');
    console.log(JSON.stringify(vehicle, null, 2));
    
    console.log('\n' + '='.repeat(80));
    console.log('KEY FIELDS FOR ROUTE OPTIMIZATION');
    console.log('='.repeat(80));
    
    console.log('\n1️⃣  SEAT CAPACITY:');
    console.log(`   vehicle.seatCapacity = ${vehicle.seatCapacity}`);
    console.log(`   vehicle.capacity = ${JSON.stringify(vehicle.capacity)}`);
    console.log(`   vehicle.seatingCapacity = ${vehicle.seatingCapacity}`);
    
    console.log('\n2️⃣  DRIVER ASSIGNMENT:');
    console.log(`   vehicle.assignedDriver = ${JSON.stringify(vehicle.assignedDriver, null, 2)}`);
    console.log(`   vehicle.driver = ${JSON.stringify(vehicle.driver)}`);
    console.log(`   vehicle.driverId = ${vehicle.driverId}`);
    
    console.log('\n3️⃣  STATUS:');
    console.log(`   vehicle.status = ${vehicle.status}`);
    
    console.log('\n4️⃣  ORGANIZATION:');
    console.log(`   vehicle.organizationName = ${vehicle.organizationName}`);
    console.log(`   vehicle.companyName = ${vehicle.companyName}`);
    console.log(`   vehicle.emailDomain = ${vehicle.emailDomain}`);
    
    console.log('\n' + '='.repeat(80));
    console.log('DIAGNOSIS');
    console.log('='.repeat(80));
    
    const hasCapacity = vehicle.seatCapacity > 0 || vehicle.capacity?.passengers > 0;
    const hasDriver = !!(vehicle.assignedDriver || vehicle.driver || vehicle.driverId);
    const isActive = vehicle.status && vehicle.status.toLowerCase() === 'active';
    
    console.log(`\n✅ Has Seat Capacity: ${hasCapacity}`);
    console.log(`${hasDriver ? '✅' : '❌'} Has Driver: ${hasDriver}`);
    console.log(`✅ Is Active: ${isActive}`);
    
    if (!hasDriver) {
      console.log('\n🚨 PROBLEM FOUND: NO DRIVER ASSIGNED!');
      console.log('\nThe vehicle has NO driver in any of these fields:');
      console.log('   - assignedDriver');
      console.log('   - driver');
      console.log('   - driverId');
      console.log('\nThis is why route optimization is not using this vehicle!');
    }
    
    console.log('\n' + '='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

showVehicleStructure();
