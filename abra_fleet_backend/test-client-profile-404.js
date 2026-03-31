// test-client-profile-404.js
// Debug script to find why client profile returns 404

const mongoose = require('mongoose');
require('dotenv').config();

async function debugClientProfile() {
  try {
    console.log('\n🔍 DEBUGGING CLIENT PROFILE 404 ERROR');
    console.log('═'.repeat(80));

    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    const db = mongoose.connection.db;

    // 1. Check all clients in database
    console.log('\n📊 STEP 1: Checking all clients in database');
    console.log('─'.repeat(80));
    
    const allClients = await db.collection('clients').find({}).toArray();
    console.log(`Found ${allClients.length} clients in database:`);
    
    allClients.forEach((client, index) => {
      console.log(`\n${index + 1}. Client:`);
      console.log(`   _id: ${client._id}`);
      console.log(`   email: ${client.email}`);
      console.log(`   name: ${client.name}`);
      console.log(`   role: ${client.role}`);
      console.log(`   status: ${client.status}`);
    });

    // 2. Check if there are any users with role 'client' in users collection
    console.log('\n📊 STEP 2: Checking users collection for client role');
    console.log('─'.repeat(80));
    
    const clientUsers = await db.collection('users').find({ role: 'client' }).toArray();
    console.log(`Found ${clientUsers.length} users with role 'client':`);
    
    clientUsers.forEach((user, index) => {
      console.log(`\n${index + 1}. User:`);
      console.log(`   _id: ${user._id}`);
      console.log(`   email: ${user.email}`);
      console.log(`   name: ${user.name}`);
      console.log(`   role: ${user.role}`);
    });

    // 3. Check admin_users collection
    console.log('\n📊 STEP 3: Checking admin_users collection for client role');
    console.log('─'.repeat(80));
    
    const adminClientUsers = await db.collection('admin_users').find({ role: 'client' }).toArray();
    console.log(`Found ${adminClientUsers.length} admin_users with role 'client':`);
    
    adminClientUsers.forEach((user, index) => {
      console.log(`\n${index + 1}. Admin User:`);
      console.log(`   _id: ${user._id}`);
      console.log(`   email: ${user.email}`);
      console.log(`   name: ${user.name}`);
      console.log(`   role: ${user.role}`);
    });

    // 4. Provide solution
    console.log('\n💡 SOLUTION:');
    console.log('═'.repeat(80));
    
    if (allClients.length === 0) {
      console.log('❌ NO CLIENTS FOUND IN DATABASE!');
      console.log('\nThe issue is: There are no records in the "clients" collection.');
      console.log('\nTo fix this:');
      console.log('1. Create a client account through the admin panel');
      console.log('2. Or run the client creation API endpoint');
      console.log('3. Make sure the client is created in the "clients" collection');
    } else {
      console.log('✅ Clients exist in database');
      console.log('\nThe issue might be:');
      console.log('1. JWT token contains wrong email');
      console.log('2. Client logged in with different email than stored in database');
      console.log('3. Email case mismatch (database has uppercase, JWT has lowercase)');
      console.log('\nTo fix:');
      console.log('1. Check the JWT token payload - what email is in it?');
      console.log('2. Make sure client logs in with the exact email stored in database');
      console.log('3. Check browser console for the JWT token and decode it at jwt.io');
    }

    console.log('\n═'.repeat(80));
    console.log('✅ DEBUG COMPLETE\n');

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await mongoose.disconnect();
    process.exit(0);
  }
}

debugClientProfile();
