// debug-driver-login-issue.js - Debug Driver Login Issue
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function debugDriverLoginIssue() {
  console.log('\n🔍 DEBUGGING DRIVER LOGIN ISSUE');
  console.log('═'.repeat(80));
  
  let client;
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('✅ Connected to MongoDB');
    console.log('─'.repeat(80));
    
    const targetEmail = 'amit.singh@abrafleet.com';
    
    // ========================================================================
    // STEP 1: Check All Collections for This Email
    // ========================================================================
    console.log('\n📂 STEP 1: CHECKING ALL COLLECTIONS FOR EMAIL');
    console.log('─'.repeat(40));
    console.log(`   Target email: ${targetEmail}`);
    
    const collections = [
      { name: 'admin_users', role: 'admin' },
      { name: 'drivers', role: 'driver' },
      { name: 'customers', role: 'customer' },
      { name: 'clients', role: 'client' },
      { name: 'employee_admins', role: 'employee' }
    ];
    
    const foundUsers = [];
    
    for (const collection of collections) {
      const users = await db.collection(collection.name).find({ 
        email: targetEmail.toLowerCase() 
      }).toArray();
      
      if (users.length > 0) {
        console.log(`\n   ✅ Found ${users.length} user(s) in ${collection.name}:`);
        users.forEach((user, index) => {
          console.log(`      ${index + 1}. _id: ${user._id}`);
          console.log(`         email: ${user.email}`);
          console.log(`         name: ${user.name || user.personalInfo?.firstName || 'N/A'}`);
          console.log(`         role: ${user.role || collection.role}`);
          console.log(`         driverId: ${user.driverId || 'N/A'}`);
          console.log(`         password: ${user.password ? 'SET' : 'NOT SET'}`);
          console.log(`         status: ${user.status || 'N/A'}`);
          
          foundUsers.push({
            collection: collection.name,
            user: user,
            expectedRole: collection.role
          });
        });
      } else {
        console.log(`   ❌ No users found in ${collection.name}`);
      }
    }
    
    // ========================================================================
    // STEP 2: Analyze the Issue
    // ========================================================================
    console.log('\n\n🔍 STEP 2: ANALYZING THE ISSUE');
    console.log('─'.repeat(40));
    
    if (foundUsers.length === 0) {
      console.log('❌ No users found with this email in any collection');
      return;
    }
    
    if (foundUsers.length > 1) {
      console.log('⚠️  DUPLICATE EMAIL FOUND!');
      console.log(`   Found ${foundUsers.length} users with the same email:`);
      foundUsers.forEach((item, index) => {
        console.log(`   ${index + 1}. Collection: ${item.collection}, Role: ${item.user.role || item.expectedRole}`);
      });
    }
    
    // Find the driver user
    const driverUser = foundUsers.find(item => 
      item.collection === 'drivers' || 
      (item.user.role === 'driver') ||
      (item.user.driverId)
    );
    
    if (driverUser) {
      console.log('\n✅ Found driver user:');
      console.log(`   Collection: ${driverUser.collection}`);
      console.log(`   _id: ${driverUser.user._id}`);
      console.log(`   driverId: ${driverUser.user.driverId}`);
      console.log(`   role: ${driverUser.user.role}`);
    } else {
      console.log('\n❌ No driver user found');
    }
    
    // ========================================================================
    // STEP 3: Fix the Issue
    // ========================================================================
    console.log('\n\n🔧 STEP 3: FIXING THE ISSUE');
    console.log('─'.repeat(40));
    
    if (foundUsers.length > 1) {
      console.log('Removing duplicate users from wrong collections...');
      
      for (const item of foundUsers) {
        // Keep the user only in the correct collection
        const shouldKeep = (
          (item.collection === 'drivers' && (item.user.role === 'driver' || item.user.driverId)) ||
          (item.collection === 'admin_users' && item.user.role === 'admin') ||
          (item.collection === 'customers' && item.user.role === 'customer') ||
          (item.collection === 'clients' && item.user.role === 'client') ||
          (item.collection === 'employee_admins' && item.user.role === 'employee')
        );
        
        if (!shouldKeep) {
          console.log(`   Removing user from ${item.collection} (wrong collection for role: ${item.user.role})`);
          
          await db.collection(item.collection).deleteOne({
            _id: item.user._id
          });
          
          console.log(`   ✅ Removed user ${item.user._id} from ${item.collection}`);
        } else {
          console.log(`   ✅ Keeping user in ${item.collection} (correct collection)`);
        }
      }
    }
    
    // ========================================================================
    // STEP 4: Verify Fix
    // ========================================================================
    console.log('\n\n✅ STEP 4: VERIFYING FIX');
    console.log('─'.repeat(40));
    
    console.log('Checking collections again...');
    
    for (const collection of collections) {
      const users = await db.collection(collection.name).find({ 
        email: targetEmail.toLowerCase() 
      }).toArray();
      
      if (users.length > 0) {
        console.log(`   ✅ ${collection.name}: ${users.length} user(s)`);
        users.forEach(user => {
          console.log(`      - Role: ${user.role || collection.role}, DriverId: ${user.driverId || 'N/A'}`);
        });
      } else {
        console.log(`   ❌ ${collection.name}: 0 users`);
      }
    }
    
    console.log('\n🎯 RECOMMENDATION:');
    console.log('   Now try the driver login again with:');
    console.log('   Email: amit.singh@abrafleet.com');
    console.log('   Password: password123');
    
    console.log('\n═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ ERROR DEBUGGING DRIVER LOGIN');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
  } finally {
    if (client) {
      await client.close();
      console.log('📡 MongoDB connection closed');
    }
  }
}

// Run the debug
if (require.main === module) {
  debugDriverLoginIssue().catch(console.error);
}

module.exports = { debugDriverLoginIssue };