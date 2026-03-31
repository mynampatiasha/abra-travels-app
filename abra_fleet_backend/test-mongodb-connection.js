// Quick test to check if MongoDB is running
const { MongoClient } = require('mongodb');

async function testConnection() {
  const client = new MongoClient('mongodb://localhost:27017', {
    serverSelectionTimeoutMS: 3000
  });
  
  try {
    console.log('🔍 Testing MongoDB connection...\n');
    await client.connect();
    console.log('✅ MongoDB is RUNNING!');
    console.log('✅ Connection successful!\n');
    
    const db = client.db('abra_fleet');
    const collections = await db.listCollections().toArray();
    console.log(`📊 Found ${collections.length} collections in abra_fleet database`);
    
    return true;
  } catch (error) {
    console.log('❌ MongoDB is NOT RUNNING!');
    console.log('❌ Error:', error.message);
    console.log('\n🚨 YOU MUST START MONGODB FIRST!');
    console.log('\nTo start MongoDB, open a new terminal and run:');
    console.log('   mongod');
    console.log('\nOR if installed as service:');
    console.log('   net start MongoDB');
    return false;
  } finally {
    await client.close();
  }
}

testConnection();
