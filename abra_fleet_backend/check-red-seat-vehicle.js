// Check the specific vehicle showing red "0/3 available"
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkRedSeatVehicle() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    // Find vehicle with registration KA05GH9012 (the 3-seater)
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA05GH9012'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle KA05GH9012 not found');
      return;
    }
    
    console.log('🚗 VEHICLE DATA:');
    console.log('================');
    console.log('Registration:', vehicle.registrationNumber);
    console.log('Vehicle ID:', vehicle.vehicleId);
    console.log('Name:', vehicle.name);
    console.log('Status:', vehicle.status);
    console.log('\n📊 CAPACITY DATA:');
    console.log('================');
    console.log('seatCapacity:', vehicle.seatCapacity);
    console.log('seatingCapacity:', vehicle.seatingCapacity);
    console.log('capacity object:', JSON.stringify(vehicle.capacity, null, 2));
    
    console.log('\n👤 DRIVER DATA:');
    console.log('================');
    console.log('assignedDriver:', vehicle.assignedDriver);
    console.log('Driver is assigned:', vehicle.assignedDriver ? 'YES' : 'NO');
    
    // Check assigned rosters
    const vehicleId = vehicle._id.toString();
    const assignedRosters = await db.collection('rosters').find({
      vehicleId: vehicleId,
      status: 'assigned'
    }).toArray();
    
    console.log('\n📋 ASSIGNED ROSTERS:');
    console.log('================');
    console.log('Total assigned:', assignedRosters.length);
    
    if (assignedRosters.length > 0) {
      console.log('\nAssigned customers:');
      assignedRosters.forEach((roster, idx) => {
        console.log(`  ${idx + 1}. ${roster.customerName || 'Unknown'} (${roster.customerEmail || 'N/A'})`);
        console.log(`     Status: ${roster.status}`);
        console.log(`     Assigned at: ${roster.assignedAt}`);
      });
    }
    
    // Calculate availability
    const totalSeats = vehicle.capacity?.passengers || vehicle.seatCapacity || vehicle.seatingCapacity || 3;
    const driverSeat = vehicle.assignedDriver ? 1 : 0;
    const assignedCustomers = assignedRosters.length;
    const availableSeats = totalSeats - driverSeat - assignedCustomers;
    
    console.log('\n🧮 CALCULATION:');
    console.log('================');
    console.log(`Total seats: ${totalSeats}`);
    console.log(`Driver seat: ${driverSeat}`);
    console.log(`Assigned customers: ${assignedCustomers}`);
    console.log(`Available: ${totalSeats} - ${driverSeat} - ${assignedCustomers} = ${availableSeats}`);
    console.log(`\nDisplay: ${availableSeats}/${totalSeats} available`);
    
    console.log('\n🎨 COLOR LOGIC:');
    console.log('================');
    if (availableSeats === 0) {
      console.log('Color: 🔴 RED (vehicle is full)');
    } else if (availableSeats <= 1) {
      console.log('Color: 🟠 ORANGE (almost full)');
    } else {
      console.log('Color: 🟢 GREEN (available)');
    }
    
    console.log('\n✅ CONCLUSION:');
    console.log('================');
    if (availableSeats === 0) {
      console.log('The red color is CORRECT - vehicle is completely full!');
      console.log(`This vehicle has ${totalSeats} seats, ${driverSeat} for driver, and ${assignedCustomers} customers assigned.`);
      console.log('No more seats available for new assignments.');
    } else {
      console.log(`Vehicle should show: ${availableSeats}/${totalSeats} available`);
      console.log(`Color should be: ${availableSeats <= 1 ? 'ORANGE' : 'GREEN'}`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkRedSeatVehicle();
