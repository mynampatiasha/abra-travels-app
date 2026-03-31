require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

async function checkRosterFullData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Get the roster
    const roster = await db.collection('rosters').findOne({
      _id: new ObjectId('69412e9ab55d35f2b5e203dd')
    });
    
    console.log('📋 Full Roster Data:');
    console.log(JSON.stringify(roster, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterFullData();
