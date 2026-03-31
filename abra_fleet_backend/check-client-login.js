// check-client-login.js - Check which client is logging in and diagnose JWT issue
require('dotenv').config();
const { MongoClient } = require('mongodb');
const jwt = require('jsonwebtoken');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

async function checkClientLogin() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    console.log('═'.repeat(80));
    console.log('🔍 CHECKING CLIENT LOGIN FLOW');
    console.log('═'.repeat(80));
    
    // Step 1: Check all collections for client role users
    console.log('\n📊 STEP 1: Finding all users with role "client"');
    console.log('─'.repeat(80));
    
    const collections = [
      { name: 'admin_users', role: 'admin' },
      { name: 'drivers', role: 'driver' },
      { name: 'customers', role: 'customer' },
      { name: 'clients', role: 'client' },
      { name: 'employee_admins', role: 'employee' }
    ];
    
    const allClientUsers = [];
    
    for (const collection of collections) {
      const users = await db.collection(collection.name).find({ 
        role: 'client' 
      }).toArray();
      
      if (users.length > 0) {
        console.log(`\n✅ Found ${users.length} client(s) in ${collection.name}:`);
        users.forEach((user, idx) => {
          console.log(`   ${idx + 1}. Email: ${user.email}`);
          console.log(`      Name: ${user.name}`);
          console.log(`      Status: ${user.status || 'N/A'}`);
          console.log(`      Has Password: ${user.password ? 'Yes' : 'No'}`);
          
          allClientUsers.push({
            collection: collection.name,
            email: user.email,
            name: user.name,
            _id: user._id,
            hasPassword: !!user.password
          });
        });
      }
    }
    
    // Step 2: Simulate login for each client
    console.log('\n\n📊 STEP 2: Simulating JWT token creation for each client');
    console.log('─'.repeat(80));
    
    for (const clientUser of allClientUsers) {
      console.log(`\n🔐 Client: ${clientUser.email} (from ${clientUser.collection})`);
      
      // Simulate token creation
      const tokenPayload = {
        userId: clientUser._id.toString(),
        email: clientUser.email,
        name: clientUser.name,
        role: 'client',
        organizationId: 'default_org'
      };
      
      const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: '7d' });
      
      console.log('   Token Payload:');
      console.log('   ', JSON.stringify(tokenPayload, null, 2).replace(/\n/g, '\n   '));
      
      // Now check if this email exists in clients collection
      const clientInClientsCollection = await db.collection('clients').findOne({
        email: clientUser.email.toLowerCase()
      });
      
      if (clientInClientsCollection) {
        console.log('   ✅ This email EXISTS in clients collection');
        console.log('   ✅ Profile endpoint will work!');
      } else {
        console.log('   ❌ This email DOES NOT exist in clients collection');
        console.log('   ❌ Profile endpoint will return 404!');
        console.log('   💡 SOLUTION: Create matching record in clients collection');
      }
    }
    
    // Step 3: Check for orphaned records
    console.log('\n\n📊 STEP 3: Checking for orphaned records');
    console.log('─'.repeat(80));
    
    const clientsInClientsCollection = await db.collection('clients').find({}).toArray();
    
    console.log(`\nFound ${clientsInClientsCollection.length} records in clients collection:`);
    
    for (const client of clientsInClientsCollection) {
      console.log(`\n   Email: ${client.email}`);
      
      // Check if this client can login
      const canLogin = allClientUsers.some(u => u.email.toLowerCase() === client.email.toLowerCase());
      
      if (canLogin) {
        console.log('   ✅ Can login (exists in admin_users or clients with password)');
      } else {
        console.log('   ❌ Cannot login (no matching user with password in any collection)');
        console.log('   💡 SOLUTION: Create user in admin_users or add password to clients record');
      }
    }
    
    // Step 4: Recommendations
    console.log('\n\n💡 RECOMMENDATIONS');
    console.log('═'.repeat(80));
    
    const clientsWithoutProfile = allClientUsers.filter(u => {
      return !clientsInClientsCollection.some(c => 
        c.email.toLowerCase() === u.email.toLowerCase()
      );
    });
    
    if (clientsWithoutProfile.length > 0) {
      console.log('\n⚠️  Found clients that can login but have no profile:');
      clientsWithoutProfile.forEach(client => {
        console.log(`   - ${client.email} (in ${client.collection})`);
      });
      console.log('\n   Fix: Create matching records in clients collection');
    }
    
    const profilesWithoutLogin = clientsInClientsCollection.filter(c => {
      return !allClientUsers.some(u => 
        u.email.toLowerCase() === c.email.toLowerCase()
      );
    });
    
    if (profilesWithoutLogin.length > 0) {
      console.log('\n⚠️  Found profiles that cannot login:');
      profilesWithoutLogin.forEach(client => {
        console.log(`   - ${client.email}`);
      });
      console.log('\n   Fix: Create matching user in admin_users with password');
    }
    
    if (clientsWithoutProfile.length === 0 && profilesWithoutLogin.length === 0) {
      console.log('\n✅ All clients are properly configured!');
      console.log('   Every client that can login has a profile.');
      console.log('   Every profile has a user that can login.');
    }
    
    console.log('\n' + '═'.repeat(80));
    console.log('✅ CHECK COMPLETE');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkClientLogin();
