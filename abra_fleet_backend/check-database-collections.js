require('dotenv').config();
const { MongoClient } = require('mongodb');

async function checkDatabaseCollections() {
  console.log('🔍 Checking Database Collections\n');
  
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abrafleet');
    
    // List all collections
    const collections = await db.listCollections().toArray();
    console.log(`📚 Collections in database: ${collections.length}\n`);
    
    for (const collection of collections) {
      const count = await db.collection(collection.name).countDocuments();
      console.log(`  📁 ${collection.name}: ${count} documents`);
    }
    
    console.log('\n🔍 Checking users collection...');
    const users = await db.collection('users').find({}).limit(5).toArray();
    console.log(`  Found ${users.length} users`);
    if (users.length > 0) {
      users.forEach((u, i) => {
        console.log(`    ${i + 1}. ${u.name} (${u.email}) - Role: ${u.role}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkDatabaseCollections();
