// Script to create admin user in MongoDB with correct role
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet'; // Correct database name from .env

async function createAdminUser() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔧 Connecting to MongoDB...');
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    
    // Admin user details (must match Firestore)
    const adminEmail = 'admin@abrafleet.com';
    const adminFirebaseUid = 'qnwp8d0clDSSNuSm3ugmXYLSI3K2'; // From your logs
    const adminPassword = 'admin123'; // Note: Password is managed by Firebase Auth, not MongoDB
    
    console.log(`\n🔍 Checking for admin user: ${adminEmail}`);
    
    // Check if user already exists
    let adminUser = await db.collection('users').findOne({ email: adminEmail });
    
    if (adminUser) {
      console.log('✅ Admin user found');
      console.log('   Current role:', adminUser.role);
      
      if (adminUser.role === 'admin') {
        console.log('✅ Admin user already has correct role');
        return;
      }
      
      // Update role to admin
      console.log('\n🔧 Updating role to admin...');
      await db.collection('users').updateOne(
        { email: adminEmail },
        { 
          $set: { 
            role: 'admin',
            updatedAt: new Date()
          } 
        }
      );
      console.log('✅ Admin role updated successfully!');
      
    } else {
      console.log('❌ Admin user not found, creating new user...');
      
      // Create new admin user
      const newAdmin = {
        firebaseUid: adminFirebaseUid,
        email: adminEmail,
        name: 'System Administrator',
        role: 'admin',
        fcmToken: null,
        createdAt: new Date(),
        updatedAt: new Date(),
        lastLogin: new Date(),
        isActive: true
      };
      
      await db.collection('users').insertOne(newAdmin);
      console.log('✅ Admin user created successfully!');
    }
    
    // Verify final state
    adminUser = await db.collection('users').findOne({ email: adminEmail });
    console.log('\n📋 Final admin user state:');
    console.log('   Email:', adminUser.email);
    console.log('   Role:', adminUser.role);
    console.log('   Firebase UID:', adminUser.firebaseUid);
    console.log('   Name:', adminUser.name);
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    throw error;
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

// Run the script
createAdminUser()
  .then(() => {
    console.log('\n✅ Script completed successfully');
    console.log('\n📝 Next steps:');
    console.log('   1. Restart the backend server');
    console.log('   2. Hot reload the Flutter app (press "r" in terminal)');
    console.log('   3. Login as admin@abrafleet.com');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Script failed:', error);
    process.exit(1);
  });
