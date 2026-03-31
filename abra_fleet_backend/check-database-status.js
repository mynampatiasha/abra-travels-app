require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet'; // Correct database name from .env

async function checkDatabase() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('📊 Database Status Check\n');
    console.log('='.repeat(60) + '\n');
    
    // Check vehicles
    const vehicleCount = await db.collection('vehicles').countDocuments();
    console.log(`Vehicles: ${vehicleCount}`);
    if (vehicleCount > 0) {
      const vehicles = await db.collection('vehicles').find().limit(3).toArray();
      vehicles.forEach(v => {
        console.log(`  - ${v.vehicleNumber || v.registrationNumber || 'N/A'} (${v.vehicleType || v.type || 'N/A'}) - Active: ${v.isActive !== false}`);
      });
    }
    console.log('');
    
    // Check rosters
    const rosterCount = await db.collection('rosters').countDocuments();
    const pendingCount = await db.collection('rosters').countDocuments({ status: 'pending' });
    console.log(`Rosters: ${rosterCount} (${pendingCount} pending)`);
    if (pendingCount > 0) {
      const rosters = await db.collection('rosters').find({ status: 'pending' }).limit(3).toArray();
      rosters.forEach(r => {
        console.log(`  - ${r.customerName} - ${r.pickupLocation}`);
      });
    }
    console.log('');
    
    // Check trips
    const tripCount = await db.collection('trips').countDocuments();
    console.log(`Trips: ${tripCount}`);
    if (tripCount > 0) {
      const trips = await db.collection('trips').find().limit(3).toArray();
      trips.forEach(t => {
        const customerName = t.customer?.name || t.customerName || 'N/A';
        console.log(`  - ${t.tripNumber || t._id} - ${customerName} (${t.status})`);
      });
    }
    console.log('');
    
    // Check drivers
    const driverCount = await db.collection('drivers').countDocuments();
    console.log(`Drivers: ${driverCount}`);
    if (driverCount > 0) {
      const drivers = await db.collection('drivers').find().limit(3).toArray();
      drivers.forEach(d => {
        console.log(`  - ${d.name} (${d.email})`);
      });
    }
    console.log('');
    
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await client.close();
  }
}

checkDatabase();
