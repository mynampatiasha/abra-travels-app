const { MongoClient } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkAvailableRosters() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet'); // Fixed: using correct database name from .env
    
    // Count all rosters
    const totalRosters = await db.collection('rosters').countDocuments();
    console.log(`📊 Total rosters in database: ${totalRosters}\n`);
    
    if (totalRosters === 0) {
      console.log('❌ NO ROSTERS FOUND IN DATABASE!');
      console.log('   This explains why auto mode shows "0 customers assigned"');
      console.log('   The roster IDs from the frontend do not exist in the database.\n');
      return;
    }
    
    // Group by status
    console.log('📋 Rosters by status:');
    const statusCounts = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]).toArray();
    
    statusCounts.forEach(stat => {
      console.log(`   ${stat._id || 'null'}: ${stat.count}`);
    });
    
    // Show some sample rosters
    console.log('\n📋 Sample rosters (first 10):');
    const sampleRosters = await db.collection('rosters').find().limit(10).toArray();
    
    sampleRosters.forEach((roster, index) => {
      console.log(`\n   ${index + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`      ID: ${roster._id}`);
      console.log(`      Status: ${roster.status}`);
      console.log(`      Email: ${roster.customerEmail || 'N/A'}`);
      console.log(`      Organization: ${roster.organization || roster.organizationName || 'N/A'}`);
      console.log(`      Created: ${roster.createdAt || 'N/A'}`);
    });
    
    // Check for rosters that can be assigned (not already assigned/completed/cancelled)
    const assignableRosters = await db.collection('rosters').countDocuments({
      status: { $nin: ['assigned', 'completed', 'cancelled', 'rejected'] }
    });
    
    console.log(`\n✅ Assignable rosters (not assigned/completed/cancelled): ${assignableRosters}`);
    
    // Show assignable rosters
    if (assignableRosters > 0) {
      console.log('\n📋 Assignable rosters:');
      const assignable = await db.collection('rosters').find({
        status: { $nin: ['assigned', 'completed', 'cancelled', 'rejected'] }
      }).limit(10).toArray();
      
      assignable.forEach((roster, index) => {
        console.log(`\n   ${index + 1}. ${roster.customerName || 'Unknown'}`);
        console.log(`      ID: ${roster._id}`);
        console.log(`      Status: ${roster.status}`);
        console.log(`      Email: ${roster.customerEmail || 'N/A'}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkAvailableRosters();
