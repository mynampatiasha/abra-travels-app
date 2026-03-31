// check-client-users.js
// Check what client users exist in the database

require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function checkClientUsers() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Get all users
    const allUsers = await db.collection('users').find({}).toArray();
    console.log(`\n📊 Total users in database: ${allUsers.length}\n`);
    
    allUsers.forEach((user, index) => {
      console.log(`User ${index + 1}:`);
      console.log(`  Email: ${user.email || 'N/A'}`);
      console.log(`  Role: ${user.role || 'N/A'}`);
      console.log(`  Firebase UID: ${user.firebaseUid || 'N/A'}`);
      console.log(`  Organization ID: ${user.organizationId || 'N/A'}`);
      console.log(`  Organization Name: ${user.organizationName || 'N/A'}`);
      console.log(`  Company Name: ${user.companyName || 'N/A'}`);
      console.log('');
    });
    
    // Check for the specific user from logs
    const specificUser = await db.collection('users').findOne({ 
      firebaseUid: 'bSSJNM9JYafbxwHWgVzejpEiKQV2' 
    });
    
    if (specificUser) {
      console.log('✅ Found user bSSJNM9JYafbxwHWgVzejpEiKQV2:');
      console.log(JSON.stringify(specificUser, null, 2));
    } else {
      console.log('❌ User bSSJNM9JYafbxwHWgVzejpEiKQV2 not found in MongoDB');
      console.log('   This user might be authenticated via Firebase but not in MongoDB');
    }
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

checkClientUsers();
