const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkRosterFullDetails() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    const rosterId = '693fcc67c3a6100b317028cd'; // Rajesh Kumar
    
    const roster = await db.collection('rosters').findOne({ _id: new ObjectId(rosterId) });
    
    if (roster) {
      console.log('📋 FULL ROSTER STRUCTURE:\n');
      console.log(JSON.stringify(roster, null, 2));
    } else {
      console.log('❌ Roster not found');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterFullDetails();
