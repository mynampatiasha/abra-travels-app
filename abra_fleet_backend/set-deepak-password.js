const { MongoClient } = require('mongodb');
const bcrypt = require('bcryptjs');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra-fleet-management';

async function setDeepakPassword() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    console.log('================================================================================');
    console.log('🔧 UPDATING DRIVER PASSWORD: deepak.joshi@abrafleet.com');
    console.log('================================================================================\n');
    
    const db = client.db();
    const email = 'deepak.joshi@abrafleet.com';
    const password = 'abrafleet123';
    
    // Hash the password
    const hashedPassword = await bcrypt.hash(password, 10);
    
    // Check if driver exists
    const existingDriver = await db.collection('drivers').findOne({ email: email });
    
    if (!existingDriver) {
      console.log('❌ ERROR: Driver not found in drivers collection');
      console.log('   Email:', email);
      console.log('\n💡 Please verify the driver exists first');
      return;
    }
    
    // Update driver password
    const result = await db.collection('drivers').updateOne(
      { email: email },
      { 
        $set: { 
          password: hashedPassword,
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ UPDATED driver password in drivers collection');
    console.log('   Email:', email);
    console.log('   Password:', password);
    console.log('   Collection: drivers');
    console.log('   _id:', existingDriver._id);
    console.log('   Name:', existingDriver.name || 'N/A');
    console.log('   Phone:', existingDriver.phoneNumber || 'N/A');
    
    console.log('\n================================================================================');
    console.log('🎉 SUCCESS - Driver password updated');
    console.log('================================================================================');
    console.log('\n📝 Login Credentials:');
    console.log('   Email: deepak.joshi@abrafleet.com');
    console.log('   Password: abrafleet123');
    console.log('   Role: Driver');
    console.log('   Access: Driver Portal');
    console.log('\n⚠️  NOTE: This is a DRIVER account');
    console.log('   - Can access driver portal');
    console.log('   - Can view assigned trips/rosters');
    console.log('   - Can update trip status');
    console.log('   - Can view notifications');
    console.log('\n================================================================================\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.log('\n💡 Make sure MongoDB is running:');
    console.log('   Run: start-mongodb.bat');
  } finally {
    await client.close();
  }
}

setDeepakPassword();
