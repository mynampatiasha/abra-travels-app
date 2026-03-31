const { MongoClient } = require('mongodb');
require('dotenv').config();

async function testDriverRole() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Check admin_users collection
    console.log('\n🔍 Checking admin_users collection...');
    const adminUser = await db.collection('admin_users').findOne({ 
      email: 'drivertest@gmail.com' 
    });
    
    if (adminUser) {
      console.log('✅ Found in admin_users:');
      console.log('   Email:', adminUser.email);
      console.log('   Role:', adminUser.role);
      console.log('   Firebase UID:', adminUser.firebaseUid);
    } else {
      console.log('❌ NOT found in admin_users collection');
    }
    
    // Check drivers collection
    console.log('\n🔍 Checking drivers collection...');
    const driver = await db.collection('drivers').findOne({ 
      'personalInfo.email': 'drivertest@gmail.com' 
    });
    
    if (driver) {
      console.log('✅ Found in drivers:');
      console.log('   Email:', driver.personalInfo.email);
      console.log('   Driver ID:', driver.driverId);
      console.log('   Firebase UID:', driver.uid);
      console.log('   Status:', driver.status);
    } else {
      console.log('❌ NOT found in drivers collection');
    }
    
    // Check users collection (legacy)
    console.log('\n🔍 Checking users collection...');
    const user = await db.collection('users').findOne({ 
      email: 'drivertest@gmail.com' 
    });
    
    if (user) {
      console.log('✅ Found in users:');
      console.log('   Email:', user.email);
      console.log('   Role:', user.role);
      console.log('   Firebase UID:', user.firebaseUid);
    } else {
      console.log('❌ NOT found in users collection');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Disconnected from MongoDB');
  }
}

testDriverRole();