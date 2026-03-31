// Check specific vehicles VH143864 and VH143866
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkVehicles() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    console.log('='*80);
    console.log('🔍 CHECKING SPECIFIC VEHICLES');
    console.log('='*80);
    
    const vehicleNumbers = ['VH143864', 'VH143866'];
    
    for (const vehicleNum of vehicleNumbers) {
      console.log(`\n🚗 Searching for: ${vehicleNum}`);
      console.log('-'*60);
      
      // Try different field names
      const vehicle = await db.collection('vehicles').findOne({
        $or: [
          { vehicleNumber: vehicleNum },
          { registrationNumber: vehicleNum },
          { name: vehicleNum },
          { licensePlate: vehicleNum }
        ]
      });
      
      if (vehicle) {
        console.log('✅ VEHICLE FOUND!');
        console.log('\n📋 Complete Vehicle Data:');
        console.log(JSON.stringify(vehicle, null, 2));
        
        console.log('\n📊 Key Fields:');
        console.log(`   - _id: ${vehicle._id}`);
        console.log(`   - name: ${vehicle.name}`);
        console.log(`   - vehicleNumber: ${vehicle.vehicleNumber}`);
        console.log(`   - registrationNumber: ${vehicle.registrationNumber}`);
        console.log(`   - status: ${vehicle.status}`);
        
        // Check capacity fields
        console.log('\n💺 Capacity Information:');
        console.log(`   - seatCapacity: ${vehicle.seatCapacity}`);
        console.log(`   - seatingCapacity: ${vehicle.seatingCapacity}`);
        console.log(`   - capacity: ${JSON.stringify(vehicle.capacity)}`);
        
        // Determine actual capacity
        let totalSeats = 4; // default
        if (vehicle.capacity?.passengers) {
          totalSeats = vehicle.capacity.passengers;
          console.log(`   ✅ Using capacity.passengers: ${totalSeats}`);
        } else if (vehicle.seatCapacity) {
          totalSeats = vehicle.seatCapacity;
          console.log(`   ✅ Using seatCapacity: ${totalSeats}`);
        } else if (vehicle.seatingCapacity) {
          totalSeats = vehicle.seatingCapacity;
          console.log(`   ✅ Using seatingCapacity: ${totalSeats}`);
        }
        
        // Check driver
        console.log('\n👤 Driver Information:');
        console.log(`   - assignedDriver: ${JSON.stringify(vehicle.assignedDriver)}`);
        const hasDriver = vehicle.assignedDriver != null;
        console.log(`   - Has driver: ${hasDriver ? 'YES' : 'NO'}`);
        
        // Check assigned customers
        console.log('\n👥 Current Assignments:');
        const assignedRosters = await db.collection('rosters').find({
          vehicleId: vehicle._id.toString(),
          status: 'assigned',
          assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
        }).toArray();
        
        console.log(`   - Assigned rosters today: ${assignedRosters.length}`);
        
        if (assignedRosters.length > 0) {
          console.log('\n   📋 Assigned Customers:');
          assignedRosters.forEach((roster, idx) => {
            console.log(`      ${idx + 1}. ${roster.customerName || 'Unknown'}`);
            console.log(`         - Email: ${roster.customerEmail || 'N/A'}`);
            console.log(`         - Time: ${roster.startTime || 'N/A'}`);
            console.log(`         - Type: ${roster.rosterType || 'N/A'}`);
          });
        }
        
        // Calculate availability
        const driverSeat = hasDriver ? 1 : 0;
        const assignedSeats = assignedRosters.length;
        const availableSeats = totalSeats - driverSeat - assignedSeats;
        
        console.log('\n📊 SEAT CALCULATION:');
        console.log(`   - Total seats: ${totalSeats}`);
        console.log(`   - Driver seat: ${driverSeat}`);
        console.log(`   - Assigned customers: ${assignedSeats}`);
        console.log(`   - Available seats: ${availableSeats}`);
        console.log(`   - Display: "${availableSeats}/${totalSeats} seats available"`);
        
        // Check if this matches what user reported
        const userReported = vehicleNum === 'VH143864' ? '39/40' : '14/15';
        console.log(`\n⚠️  User reported: "${userReported} seats available"`);
        console.log(`   Actual should be: "${availableSeats}/${totalSeats} seats available"`);
        
        if (userReported !== `${availableSeats}/${totalSeats}`) {
          console.log(`   ❌ MISMATCH! Data is incorrect!`);
        } else {
          console.log(`   ✅ MATCH! Data is correct!`);
        }
        
      } else {
        console.log('❌ VEHICLE NOT FOUND');
        console.log('   Searched in fields: vehicleNumber, registrationNumber, name, licensePlate');
      }
    }
    
    // Also search for vehicles with 40 or 15 seat capacity
    console.log('\n\n' + '='*80);
    console.log('🔍 SEARCHING FOR VEHICLES WITH 40 OR 15 SEAT CAPACITY');
    console.log('='*80);
    
    const largeVehicles = await db.collection('vehicles').find({
      $or: [
        { seatCapacity: 40 },
        { seatingCapacity: 40 },
        { 'capacity.passengers': 40 },
        { seatCapacity: 15 },
        { seatingCapacity: 15 },
        { 'capacity.passengers': 15 }
      ]
    }).toArray();
    
    console.log(`\nFound ${largeVehicles.length} vehicles with 40 or 15 seat capacity:`);
    
    for (const v of largeVehicles) {
      const capacity = v.capacity?.passengers || v.seatCapacity || v.seatingCapacity || 'Unknown';
      const name = v.name || v.vehicleNumber || v.registrationNumber || 'Unknown';
      console.log(`\n🚗 ${name}`);
      console.log(`   - Capacity: ${capacity} seats`);
      console.log(`   - Status: ${v.status}`);
      console.log(`   - Driver: ${v.assignedDriver ? 'Assigned' : 'Not assigned'}`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkVehicles();
