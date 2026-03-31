// Check actual roster structure in database
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkRosterStructure() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const rosters = await db.collection('rosters').find({}).limit(3).toArray();
    
    console.log('\n📋 Roster Structure in Database:\n');
    console.log(JSON.stringify(rosters, null, 2));
    
    console.log('\n' + '='.repeat(80));
    console.log(`Total rosters in database: ${await db.collection('rosters').countDocuments()}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterStructure();
