// check-all-collections.js
// Check all collections and find the user

require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function checkAllCollections() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    // List all collections
    const collections = await db.listCollections().toArray();
    console.log(`\n📊 Collections in database:\n`);
    collections.forEach(col => console.log(`  - ${col.name}`));
    
    // Search for the user in different collections
    const userId = 'bSSJNM9JYafbxwHWgVzejpEiKQV2';
    console.log(`\n🔍 Searching for user: ${userId}\n`);
    
    // Check clients collection
    const clientsCol = db.collection('clients');
    const clientByFirebaseUid = await clientsCol.findOne({ firebaseUid: userId });
    const clientByUserId = await clientsCol.findOne({ userId: userId });
    const clientById = await clientsCol.findOne({ _id: userId });
    
    if (clientByFirebaseUid) {
      console.log('✅ Found in clients collection (by firebaseUid):');
      console.log(JSON.stringify(clientByFirebaseUid, null, 2));
    } else if (clientByUserId) {
      console.log('✅ Found in clients collection (by userId):');
      console.log(JSON.stringify(clientByUserId, null, 2));
    } else if (clientById) {
      console.log('✅ Found in clients collection (by _id):');
      console.log(JSON.stringify(clientById, null, 2));
    } else {
      console.log('❌ Not found in clients collection');
    }
    
    // Check organizations collection
    const orgsCol = db.collection('organizations');
    const orgByFirebaseUid = await orgsCol.findOne({ firebaseUid: userId });
    const orgByUserId = await orgsCol.findOne({ userId: userId });
    
    if (orgByFirebaseUid) {
      console.log('\n✅ Found in organizations collection (by firebaseUid):');
      console.log(JSON.stringify(orgByFirebaseUid, null, 2));
    } else if (orgByUserId) {
      console.log('\n✅ Found in organizations collection (by userId):');
      console.log(JSON.stringify(orgByUserId, null, 2));
    } else {
      console.log('\n❌ Not found in organizations collection');
    }
    
    // Check customers collection
    const customersCol = db.collection('customers');
    const customerByFirebaseUid = await customersCol.findOne({ firebaseUid: userId });
    const customerByUserId = await customersCol.findOne({ userId: userId });
    
    if (customerByFirebaseUid) {
      console.log('\n✅ Found in customers collection (by firebaseUid):');
      console.log(JSON.stringify(customerByFirebaseUid, null, 2));
    } else if (customerByUserId) {
      console.log('\n✅ Found in customers collection (by userId):');
      console.log(JSON.stringify(customerByUserId, null, 2));
    } else {
      console.log('\n❌ Not found in customers collection');
    }
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

checkAllCollections();
