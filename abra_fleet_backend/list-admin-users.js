// List all users to find admin
const admin = require('./config/firebase');
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function listAdminUsers() {
  console.log('👥 Listing all users...\n');
  
  try {
    // List Firebase users
    const listUsersResult = await admin.auth().listUsers(100);
    console.log(`📊 Found ${listUsersResult.users.length} Firebase users:\n`);
    
    listUsersResult.users.forEach((user, index) => {
      console.log(`${index + 1}. ${user.email || 'No email'}`);
      console.log(`   UID: ${user.uid}`);
      console.log(`   Display Name: ${user.displayName || 'None'}`);
      console.log('');
    });
    
    // Check MongoDB for role information
    const client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n📊 Checking MongoDB for user roles...\n');
    const users = await db.collection('users').find({}).toArray();
    
    users.forEach((user, index) => {
      console.log(`${index + 1}. ${user.email || 'No email'}`);
      console.log(`   Role: ${user.role || 'None'}`);
      console.log(`   Firebase UID: ${user.firebaseUid || 'None'}`);
      console.log('');
    });
    
    await client.close();
    
  } catch (error) {
    console.log('❌ Error:', error.message);
  }
}

listAdminUsers();
