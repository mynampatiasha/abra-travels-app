// Script to fix admin user role in MongoDB
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abrafleet';

async function fixAdminRole() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔧 Connecting to MongoDB...');
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    
    // Find admin user
    const adminEmail = 'admin@abrafleet.com';
    console.log(`\n🔍 Looking for admin user: ${adminEmail}`);
    
    const adminUser = await db.collection('users').findOne({ email: adminEmail });
    
    if (!adminUser) {
      console.log('❌ Admin user not found in MongoDB');
      console.log('   The admin user will be created on next login');
      return;
    }
    
    console.log('✅ Admin user found');
    console.log('   Current role:', adminUser.role);
    console.log('   Firebase UID:', adminUser.firebaseUid);
    
    if (adminUser.role === 'admin') {
      console.log('✅ Admin user already has correct role');
      return;
    }
    
    // Update admin role
    console.log('\n🔧 Updating admin role to "admin"...');
    const result = await db.collection('users').updateOne(
      { email: adminEmail },
      { 
        $set: { 
          role: 'admin',
          updatedAt: new Date()
        } 
      }
    );
    
    if (result.modifiedCount > 0) {
      console.log('✅ Admin role updated successfully!');
      console.log('\n📋 Updated admin user:');
      const updatedUser = await db.collection('users').findOne({ email: adminEmail });
      console.log('   Email:', updatedUser.email);
      console.log('   Role:', updatedUser.role);
      console.log('   Firebase UID:', updatedUser.firebaseUid);
    } else {
      console.log('⚠️  No changes made');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    throw error;
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

// Run the script
fixAdminRole()
  .then(() => {
    console.log('\n✅ Script completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Script failed:', error);
    process.exit(1);
  });
