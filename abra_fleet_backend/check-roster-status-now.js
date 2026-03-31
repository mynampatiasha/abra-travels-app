const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function checkRosterStatus() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('fleet_management');
    
    const rosterIds = [
      '693fcc91c3a6100b317028d7', // Pooja Joshi
      '693fcc8dc3a6100b317028d6', // Arjun Nair
      '693fcc89c3a6100b317028d5'  // Sneha Iyer
    ];
    
    console.log('🔍 Checking status of 3 rosters...\n');
    
    for (const rosterId of rosterIds) {
      const roster = await db.collection('rosters').findOne({
        _id: new ObjectId(rosterId)
      });
      
      if (roster) {
        console.log(`📋 Roster: ${roster.customerName || 'Unknown'}`);
        console.log(`   ID: ${rosterId}`);
        console.log(`   Status: ${roster.status}`);
        console.log(`   Vehicle: ${roster.vehicleNumber || 'Not assigned'}`);
        console.log(`   Driver: ${roster.driverName || 'Not assigned'}`);
        console.log(`   Assigned At: ${roster.assignedAt || 'Never'}`);
        console.log('');
      } else {
        console.log(`❌ Roster ${rosterId} not found\n`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterStatus();
