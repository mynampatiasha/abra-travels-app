const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkAllRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('fleet_management');
    
    // Get count by status
    const statusCounts = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      }
    ]).toArray();
    
    console.log('📊 Roster counts by status:\n');
    statusCounts.forEach(item => {
      console.log(`   ${item._id || 'null'}: ${item.count}`);
    });
    
    console.log('\n' + '='.repeat(60) + '\n');
    
    // Get all rosters
    const allRosters = await db.collection('rosters').find({}).limit(20).toArray();
    
    console.log(`📋 First 20 rosters (Total: ${await db.collection('rosters').countDocuments()}):\n`);
    
    allRosters.forEach((roster, index) => {
      console.log(`${index + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`   ID: ${roster._id}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Email: ${roster.customerEmail || 'N/A'}`);
      console.log(`   Office: ${roster.officeLocation || 'N/A'}`);
      console.log(`   Vehicle: ${roster.vehicleNumber || 'Not assigned'}`);
      console.log('');
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAllRosters();
