// Check driver's vehicle assignment and vehicle check data
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function checkDriverVehicle() {
  const client = new MongoClient(MONGODB_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('abra_fleet');

    // Find driver DRV-852306
    const driver = await db.collection('drivers').findOne({
      driverId: 'DRV-852306'
    });

    if (!driver) {
      console.log('❌ Driver not found');
      return;
    }

    console.log('👤 DRIVER INFORMATION:');
    console.log('='.repeat(80));
    console.log(`Name: ${driver.personalInfo?.name || driver.name}`);
    console.log(`Driver ID: ${driver.driverId}`);
    console.log(`Firebase UID: ${driver.uid}`);
    console.log(`Assigned Vehicle: ${driver.assignedVehicle || 'None'}`);
    console.log(`Vehicle Number: ${driver.vehicleNumber || 'None'}`);

    // Check if vehicle exists
    let vehicle = null;
    
    if (driver.assignedVehicle) {
      // Try to find by vehicleNumber
      vehicle = await db.collection('vehicles').findOne({
        vehicleNumber: driver.assignedVehicle
      });
      
      if (!vehicle) {
        // Try to find by registrationNumber
        vehicle = await db.collection('vehicles').findOne({
          registrationNumber: driver.assignedVehicle
        });
      }
    }

    if (driver.vehicleNumber) {
      vehicle = await db.collection('vehicles').findOne({
        vehicleNumber: driver.vehicleNumber
      });
    }

    console.log('\n🚗 VEHICLE INFORMATION:');
    console.log('='.repeat(80));
    if (vehicle) {
      console.log('✅ Vehicle found in database:');
      console.log(JSON.stringify({
        _id: vehicle._id,
        vehicleNumber: vehicle.vehicleNumber,
        registrationNumber: vehicle.registrationNumber,
        model: vehicle.model,
        make: vehicle.make,
        capacity: vehicle.capacity,
        fuelType: vehicle.fuelType,
        status: vehicle.status
      }, null, 2));
    } else {
      console.log('❌ Vehicle NOT found in database');
      console.log('   Driver has assignedVehicle:', driver.assignedVehicle);
      console.log('   Driver has vehicleNumber:', driver.vehicleNumber);
    }

    // Check rosters for vehicle info
    console.log('\n📋 ROSTERS VEHICLE INFO:');
    console.log('='.repeat(80));
    const rosters = await db.collection('rosters').find({
      driverId: 'DRV-852306'
    }).toArray();

    console.log(`Found ${rosters.length} rosters\n`);
    
    for (const roster of rosters) {
      console.log(`Customer: ${roster.customerName}`);
      console.log(`  vehicleNumber: ${roster.vehicleNumber || 'None'}`);
      console.log(`  assignedVehicle: ${roster.assignedVehicle || 'None'}`);
      
      // Try to find vehicle from roster
      if (roster.vehicleNumber) {
        const rosterVehicle = await db.collection('vehicles').findOne({
          vehicleNumber: roster.vehicleNumber
        });
        console.log(`  Vehicle exists: ${rosterVehicle ? '✅ Yes' : '❌ No'}`);
      }
      console.log('');
    }

    // List all vehicles to see what's available
    console.log('\n🚙 ALL VEHICLES IN DATABASE:');
    console.log('='.repeat(80));
    const allVehicles = await db.collection('vehicles').find({}).toArray();
    console.log(`Total vehicles: ${allVehicles.length}\n`);
    
    for (const v of allVehicles) {
      console.log(`${v.vehicleNumber || v.registrationNumber} - ${v.model} (${v.status})`);
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkDriverVehicle();
