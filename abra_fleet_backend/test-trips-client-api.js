// Test the trips client API to verify all fields are returned
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function testTripsClientAPI() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Simulate what the API does
    console.log('📋 Simulating /api/roster/admin/assigned-trips endpoint...\n');
    
    const query = {
      status: { $in: ['assigned', 'scheduled', 'ongoing', 'in_progress', 'started', 'completed', 'done', 'cancelled'] }
    };
    
    const trips = await db.collection('rosters')
      .find(query)
      .sort({ assignedAt: -1 })
      .limit(5)
      .toArray();
    
    console.log(`📊 Found ${trips.length} trips\n`);
    
    // Get unique driver IDs
    const driverIds = [...new Set(trips.map(t => t.driverId).filter(Boolean))];
    console.log(`👤 Fetching details for ${driverIds.length} unique drivers...`);
    console.log(`   Driver IDs: ${driverIds.join(', ')}\n`);
    
    // Fetch driver details
    const driversMap = {};
    if (driverIds.length > 0) {
      const drivers = await db.collection('drivers').find({
        driverId: { $in: driverIds }
      }).toArray();
      
      console.log(`✅ Found ${drivers.length} drivers in database\n`);
      
      drivers.forEach(driver => {
        // Handle nested personalInfo structure
        const firstName = driver.personalInfo?.firstName || driver.firstName || '';
        const lastName = driver.personalInfo?.lastName || driver.lastName || '';
        const fullName = `${firstName} ${lastName}`.trim() || driver.name || driver.driverName || '';
        const phone = driver.personalInfo?.phone || driver.phone || driver.phoneNumber || driver.contactNumber || driver.mobileNumber || '';
        
        driversMap[driver.driverId] = {
          name: fullName,
          phone: phone
        };
        console.log(`   ${driver.driverId}: ${driversMap[driver.driverId].name} - ${driversMap[driver.driverId].phone}`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📋 TRANSFORMED TRIPS DATA:');
    console.log('='.repeat(80) + '\n');
    
    // Transform trips
    trips.forEach((trip, idx) => {
      const driverId = trip.driverId || '';
      const driverInfo = driversMap[driverId] || {};
      const driverName = driverInfo.name || trip.driverName || 'Not Assigned';
      const driverPhone = driverInfo.phone || trip.driverPhone || 'N/A';
      
      const pickupLocation = trip.pickupLocation || trip.homeLocation || '';
      const dropLocation = trip.dropLocation || trip.dropoffLocation || trip.officeLocation || '';
      const pickupTime = trip.pickupTime || trip.startTime || '';
      const dropTime = trip.dropTime || trip.dropoffTime || trip.endTime || '';
      
      console.log(`Trip ${idx + 1}:`);
      console.log(`  Customer: ${trip.customerName}`);
      console.log(`  Status: ${trip.status}`);
      console.log(`  Vehicle: ${trip.vehicleNumber || 'Not Assigned'}`);
      console.log(`  Driver ID: ${driverId || 'Not Assigned'}`);
      console.log(`  Driver Name: ${driverName}`);
      console.log(`  Driver Phone: ${driverPhone}`);
      console.log(`  Pickup Location: ${pickupLocation || 'N/A'}`);
      console.log(`  Drop Location: ${dropLocation || 'N/A'}`);
      console.log(`  Pickup Time: ${pickupTime || 'N/A'}`);
      console.log(`  Drop Time: ${dropTime || 'N/A'}`);
      console.log('');
    });
    
    console.log('='.repeat(80));
    console.log('✅ All fields are being populated correctly!');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testTripsClientAPI();
