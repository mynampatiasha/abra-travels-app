const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkPendingRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('fleet_management');
    
    const pendingRosters = await db.collection('rosters').find({
      status: 'pending_assignment'
    }).toArray();
    
    console.log(`📊 Found ${pendingRosters.length} pending rosters:\n`);
    
    pendingRosters.forEach((roster, index) => {
      console.log(`${index + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`   ID: ${roster._id}`);
      console.log(`   Email: ${roster.customerEmail || 'N/A'}`);
      console.log(`   Office: ${roster.officeLocation || 'N/A'}`);
      console.log(`   Type: ${roster.rosterType || 'N/A'}`);
      console.log(`   Start Date: ${roster.startDate}`);
      console.log('');
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkPendingRosters();
