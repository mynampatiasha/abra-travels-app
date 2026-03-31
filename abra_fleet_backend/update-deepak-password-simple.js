const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

// Use the same connection as the backend
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://abrafleet:9HglPyQjEYL0Wd6P@abrafleet.yfpno.mongodb.net/abra-fleet-management?retryWrites=true&w=majority';

async function updateDeepakPassword() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');
    console.log('================================================================================');
    console.log('🔧 UPDATING DRIVER PASSWORD: deepak.joshi@abrafleet.com');
    console.log('================================================================================\n');
    
    const email = 'pooja.joshi@abrafleet.com';
    const password = 'abrafleet123';
    
    // Hash the password
    const hashedPassword = await bcrypt.hash(password, 10);
    
    // Get the customers collection
    const Driver = mongoose.connection.collection('customers');
    
    // Check if driver exists
    const existingDriver = await Driver.findOne({ email: email });
    
    if (!existingDriver) {
      console.log('❌ ERROR: Driver not found in customers collection');
      console.log('   Email:', email);
      console.log('\n💡 Please verify the driver exists first');
      await mongoose.disconnect();
      return;
    }
    
    // Update driver password
    await Driver.updateOne(
      { email: email },
      { 
        $set: { 
          password: hashedPassword,
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ UPDATED driver password in customers collection');
    console.log('   Email:', email);
    console.log('   Password:', password);
    console.log('   Collection: customers');
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
    console.log('\n================================================================================\n');
    
    await mongoose.disconnect();
    console.log('✅ Disconnected from MongoDB');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

updateDeepakPassword();
