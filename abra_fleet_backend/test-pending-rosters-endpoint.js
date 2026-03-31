require('dotenv').config();
const { MongoClient } = require('mongodb');

async function testPendingRostersEndpoint() {
  console.log('🧪 Testing Pending Rosters Endpoint\n');
  
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abrafleet');
    
    // Test query - same as the endpoint
    const query = {
      status: { $in: ['pending_assignment', 'pending', 'created'] }
    };
    
    console.log('📋 Query:', JSON.stringify(query, null, 2));
    
    const rosters = await db.collection('rosters')
      .find(query)
      .sort({ createdAt: -1 })
      .limit(10)
      .toArray();
    
    console.log(`\n📊 Found ${rosters.length} pending rosters\n`);
    
    if (rosters.length > 0) {
      console.log('📝 Sample roster:');
      const sample = rosters[0];
      console.log({
        _id: sample._id,
        customerName: sample.customerName,
        customerEmail: sample.customerEmail,
        status: sample.status,
        rosterType: sample.rosterType,
        officeLocation: sample.officeLocation,
        startDate: sample.startDate,
        createdAt: sample.createdAt
      });
    } else {
      console.log('⚠️ No pending rosters found in database');
      console.log('\n🔍 Checking all rosters...');
      
      const allRosters = await db.collection('rosters')
        .find({})
        .limit(5)
        .toArray();
      
      console.log(`📊 Total rosters in database: ${await db.collection('rosters').countDocuments()}`);
      
      if (allRosters.length > 0) {
        console.log('\n📝 Sample roster statuses:');
        allRosters.forEach((r, i) => {
          console.log(`  ${i + 1}. Status: ${r.status}, Type: ${r.rosterType}, Customer: ${r.customerName}`);
        });
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

testPendingRostersEndpoint();
