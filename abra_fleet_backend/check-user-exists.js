// Quick script to check if user exists in MongoDB
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('./models/User');

async function checkUser() {
  try {
    // Connect to MongoDB using the same URI as the backend
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    // Check if user exists
    const email = 'chandrika123@abrafleet.com';
    const user = await User.findOne({ email: email.toLowerCase() });
    
    if (user) {
      console.log('✅ User found in MongoDB:');
      console.log('   Name:', user.name);
      console.log('   Email:', user.email);
      console.log('   Role:', user.role);
      console.log('   Active:', user.isActive);
      console.log('   Firebase UID:', user.firebaseUid);
    } else {
      console.log('❌ User NOT found in MongoDB');
      console.log('   Email searched:', email);
      
      // Let's see what users exist
      const allUsers = await User.find({}, 'name email role isActive');
      console.log('\n📋 All users in database:');
      if (allUsers.length === 0) {
        console.log('   No users found in database!');
      } else {
        allUsers.forEach(u => {
          console.log(`   ${u.email} - ${u.name} (${u.role}) - ${u.isActive ? 'Active' : 'Inactive'}`);
        });
      }
    }

  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await mongoose.disconnect();
    console.log('✅ Disconnected from MongoDB');
  }
}

checkUser();