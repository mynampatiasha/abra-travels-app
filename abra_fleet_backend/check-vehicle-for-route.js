// Check vehicle data for route optimization
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkVehicle() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const vehicleId = '68ddeb3f4eff4fbe00488ec8';
    
    console.log(`\n🔍 Checking vehicle: ${vehicleId}`);
    
    const vehicle = await db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle not found!');
      return;
    }
    
    console.log('\n✅ Vehicle found:');
    console.log(JSON.stringify(vehicle, null, 2));
    
    console.log('\n📋 Key fields:');
    console.log('  - _id:', vehicle._id);
    console.log('  - name:', vehicle.name);
    console.log('  - vehicleNumber:', vehicle.vehicleNumber);
    console.log('  - assignedDriver:', vehicle.assignedDriver);
    console.log('  - assignedDriverId:', vehicle.assignedDriverId);
    
    // Check if driver exists
    if (vehicle.assignedDriver) {
      let driverId;
      if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver._id) {
        driverId = vehicle.assignedDriver._id;
      } else {
        driverId = vehicle.assignedDriver;
      }
      
      console.log(`\n🔍 Checking driver: ${driverId}`);
      
      const driver = await db.collection('users').findOne({
        _id: new ObjectId(driverId)
      });
      
      if (driver) {
        console.log('✅ Driver found:');
        console.log('  - _id:', driver._id);
        console.log('  - name:', driver.name);
        console.log('  - email:', driver.email);
        console.log('  - role:', driver.role);
      } else {
        console.log('❌ Driver not found!');
      }
    } else {
      console.log('\n⚠️  No driver assigned to vehicle');
    }
    
    // Check existing assignments
    console.log('\n🔍 Checking existing roster assignments...');
    const existingAssignments = await db.collection('rosters').find({
      vehicleId: vehicleId,
      status: 'assigned',
      assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
    }).toArray();
    
    console.log(`Found ${existingAssignments.length} existing assignments`);
    if (existingAssignments.length > 0) {
      existingAssignments.forEach((roster, idx) => {
        console.log(`\n  ${idx + 1}. ${roster.customerName || 'Unknown'}`);
        console.log(`     - Roster ID: ${roster._id}`);
        console.log(`     - Organization: ${roster.organization || roster.organizationName || 'Unknown'}`);
        console.log(`     - Status: ${roster.status}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkVehicle();
