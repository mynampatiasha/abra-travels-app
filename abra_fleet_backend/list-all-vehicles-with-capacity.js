// List all vehicles with their capacity information
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function listAllVehicles() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log('='*80);
    console.log(`📊 ALL VEHICLES IN DATABASE (${vehicles.length} total)`);
    console.log('='*80);
    
    for (let i = 0; i < vehicles.length; i++) {
      const v = vehicles[i];
      
      // Get vehicle name
      const name = v.name || v.vehicleNumber || v.registrationNumber || 'Unknown';
      
      // Get capacity
      let totalSeats = 4;
      if (v.capacity?.passengers) {
        totalSeats = v.capacity.passengers;
      } else if (v.seatCapacity) {
        totalSeats = v.seatCapacity;
      } else if (v.seatingCapacity) {
        totalSeats = v.seatingCapacity;
      }
      
      // Check driver
      const hasDriver = v.assignedDriver != null;
      
      // Check assigned customers
      const assignedRosters = await db.collection('rosters').find({
        vehicleId: v._id.toString(),
        status: 'assigned',
        assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
      }).toArray();
      
      const driverSeat = hasDriver ? 1 : 0;
      const assignedSeats = assignedRosters.length;
      const availableSeats = totalSeats - driverSeat - assignedSeats;
      
      console.log(`\n${i + 1}. 🚗 ${name}`);
      console.log(`   - Status: ${v.status || 'Unknown'}`);
      console.log(`   - Driver: ${hasDriver ? 'Assigned' : 'Not assigned'}`);
      console.log(`   - Total seats: ${totalSeats}`);
      console.log(`   - Assigned customers: ${assignedSeats}`);
      console.log(`   - Available: ${availableSeats}/${totalSeats} seats`);
      
      // Highlight if this matches user's report
      if (availableSeats === 39 && totalSeats === 40) {
        console.log(`   ⚠️  THIS MATCHES USER REPORT: "39/40 seats available"`);
      }
      if (availableSeats === 14 && totalSeats === 15) {
        console.log(`   ⚠️  THIS MATCHES USER REPORT: "14/15 seats available"`);
      }
      
      if (assignedRosters.length > 0) {
        console.log(`   📋 Assigned to:`);
        assignedRosters.forEach((r, idx) => {
          console.log(`      ${idx + 1}. ${r.customerName || 'Unknown'} (${r.customerEmail || 'N/A'})`);
        });
      }
    }
    
    console.log('\n' + '='*80);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

listAllVehicles();
