// Script to clear existing readable IDs so we can regenerate them properly
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function clearRosterIds() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    
    console.log('🧹 Clearing existing readable IDs...');
    
    // Remove readableId field from all rosters
    const result = await db.collection('rosters').updateMany(
      {},
      { $unset: { readableId: "" } }
    );
    
    console.log(`✅ Cleared readable IDs from ${result.modifiedCount} rosters`);
    
    // Reset counter
    await db.collection('counters').updateOne(
      { _id: 'roster_sequence' },
      { $set: { sequence: 0 } },
      { upsert: true }
    );
    
    console.log('✅ Reset counter to 0');
    
  } catch (error) {
    console.error('❌ Error clearing roster IDs:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

clearRosterIds();