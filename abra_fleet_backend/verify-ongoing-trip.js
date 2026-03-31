// Verify the ongoing trip for customer123@abrafleet.com
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function verifyTrip() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Find ongoing trip for customer123
    const trip = await db.collection('rosters').findOne({
      customerEmail: 'customer123@abrafleet.com',
      status: 'ongoing'
    });
    
    if (!trip) {
      console.log('❌ No ongoing trip found for customer123@abrafleet.com');
      return;
    }
    
    console.log('✅ ONGOING TRIP VERIFIED!\n');
    console.log('═══════════════════════════════════════════════════════');
    console.log('📋 TRIP DETAILS');
    console.log('═══════════════════════════════════════════════════════');
    console.log(`Roster ID: ${trip._id}`);
    console.log(`Status: ${trip.status} ✅`);
    console.log(`\nCustomer:`);
    console.log(`  Name: ${trip.customerName || 'N/A'}`);
    console.log(`  Email: ${trip.customerEmail}`);
    console.log(`  Phone: ${trip.customerPhone || 'N/A'}`);
    console.log(`\nVehicle:`);
    console.log(`  Number: ${trip.vehicleNumber}`);
    console.log(`  Type: ${trip.vehicleType}`);
    console.log(`  Capacity: ${trip.seatCapacity} passengers`);
    console.log(`\nDriver:`);
    console.log(`  Name: ${trip.driverName}`);
    console.log(`  Email: ${trip.driverEmail}`);
    console.log(`  Phone: ${trip.driverPhone || 'N/A'}`);
    console.log(`\nTrip Info:`);
    console.log(`  Type: ${trip.tripType || 'N/A'}`);
    console.log(`  Date: ${trip.startDate}`);
    console.log(`  Started At: ${trip.tripStartTime}`);
    console.log(`  Pickup: ${trip.pickupLocation || 'N/A'}`);
    console.log(`  Drop: ${trip.dropLocation || 'N/A'}`);
    console.log('═══════════════════════════════════════════════════════\n');
    
    console.log('🎯 NEXT STEPS:');
    console.log('   1. Open the app/web interface');
    console.log('   2. Login with: customer123@abrafleet.com');
    console.log('   3. Navigate to "My Trips" or "Active Trips"');
    console.log('   4. You should see this trip with ONGOING status');
    console.log('   5. Test features like:');
    console.log('      - View trip details');
    console.log('      - Track driver location (if available)');
    console.log('      - Contact driver');
    console.log('      - Cancel trip (if allowed)\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

verifyTrip().catch(console.error);
