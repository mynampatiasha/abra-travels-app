// Check what roster fields are available for trips display
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function checkRosterFields() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Get a sample assigned roster
    const sampleRoster = await db.collection('rosters').findOne({
      status: { $in: ['assigned', 'scheduled', 'ongoing'] }
    });
    
    if (!sampleRoster) {
      console.log('❌ No assigned rosters found!');
      return;
    }
    
    console.log('📋 Sample Roster Fields:\n');
    console.log('='.repeat(80));
    console.log(JSON.stringify(sampleRoster, null, 2));
    console.log('='.repeat(80));
    
    console.log('\n📍 Location Fields Available:');
    console.log('  - pickupLocation:', sampleRoster.pickupLocation || 'NOT FOUND');
    console.log('  - dropoffLocation:', sampleRoster.dropoffLocation || 'NOT FOUND');
    console.log('  - homeLocation:', sampleRoster.homeLocation || 'NOT FOUND');
    console.log('  - officeLocation:', sampleRoster.officeLocation || 'NOT FOUND');
    console.log('  - currentAddress:', sampleRoster.currentAddress || 'NOT FOUND');
    console.log('  - employeeDetails.address:', sampleRoster.employeeDetails?.address || 'NOT FOUND');
    
    console.log('\n⏰ Time Fields Available:');
    console.log('  - pickupTime:', sampleRoster.pickupTime || 'NOT FOUND');
    console.log('  - dropoffTime:', sampleRoster.dropoffTime || 'NOT FOUND');
    console.log('  - startTime:', sampleRoster.startTime || 'NOT FOUND');
    console.log('  - endTime:', sampleRoster.endTime || 'NOT FOUND');
    console.log('  - fromTime:', sampleRoster.fromTime || 'NOT FOUND');
    console.log('  - toTime:', sampleRoster.toTime || 'NOT FOUND');
    
    console.log('\n👤 Driver Fields Available:');
    console.log('  - driverName:', sampleRoster.driverName || 'NOT FOUND');
    console.log('  - driverPhone:', sampleRoster.driverPhone || 'NOT FOUND');
    console.log('  - assignedDriverName:', sampleRoster.assignedDriverName || 'NOT FOUND');
    console.log('  - assignedDriverPhone:', sampleRoster.assignedDriverPhone || 'NOT FOUND');
    console.log('  - assignedDriver:', sampleRoster.assignedDriver || 'NOT FOUND');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterFields();
