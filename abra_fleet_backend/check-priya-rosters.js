require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function checkPriyaRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Check user
    const user = await db.collection('users').findOne({ 
      email: 'priya.sharma@infosys.com' 
    });
    console.log('\n📋 User:', user);
    
    // Check rosters
    const rosters = await db.collection('rosters').find({ 
      customerEmail: 'priya.sharma@infosys.com' 
    }).toArray();
    console.log('\n📋 Rosters for Priya Sharma:', rosters.length);
    rosters.forEach((roster, i) => {
      console.log(`\n${i + 1}. Roster ID: ${roster._id}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Vehicle: ${roster.vehicleNumber || 'Not assigned'}`);
      console.log(`   Driver: ${roster.driverName || 'Not assigned'}`);
      console.log(`   From: ${roster.fromDate} To: ${roster.toDate}`);
    });
    
    // Check trips
    const trips = await db.collection('trips').find({ 
      customerEmail: 'priya.sharma@infosys.com' 
    }).toArray();
    console.log('\n🚗 Trips for Priya Sharma:', trips.length);
    trips.forEach((trip, i) => {
      console.log(`\n${i + 1}. Trip ID: ${trip._id}`);
      console.log(`   Status: ${trip.status}`);
      console.log(`   Vehicle: ${trip.vehicleNumber || 'N/A'}`);
      console.log(`   Driver: ${trip.driverName || 'N/A'}`);
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    process.exit(0);
  }
}

checkPriyaRosters();
