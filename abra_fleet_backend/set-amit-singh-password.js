const mongoose = require('mongoose');
const bcrypt = require('bcrypt');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function setAmitSinghPassword() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    // Get the drivers collection
    const db = mongoose.connection.db;
    const driversCollection = db.collection('drivers');

    // Find the user
    const user = await driversCollection.findOne({ email: 'amit.singh@abrafleet.com' });
    
    if (!user) {
      console.log('❌ User not found');
      process.exit(1);
    }

    console.log('📝 Current user data:');
    console.log('Email:', user.email);
    console.log('Name:', user.name);
    console.log('Current password hash:', user.password?.substring(0, 20) + '...');
    console.log('');

    // Set new password: "amit.singh"
    const newPassword = 'amit.singh';
    const saltRounds = 12;
    const hashedPassword = await bcrypt.hash(newPassword, saltRounds);

    console.log('🔐 Setting new password...');
    console.log('New password:', newPassword);
    console.log('New hash:', hashedPassword.substring(0, 20) + '...');
    console.log('');

    // Update the password
    const result = await driversCollection.updateOne(
      { email: 'amit.singh@abrafleet.com' },
      { 
        $set: { 
          password: hashedPassword,
          updatedAt: new Date()
        } 
      }
    );

    if (result.modifiedCount > 0) {
      console.log('✅ Password updated successfully!');
      console.log('');
      console.log('📋 Login credentials:');
      console.log('Email: amit.singh@abrafleet.com');
      console.log('Password: amit.singh');
      console.log('');
      
      // Verify the password works
      const updatedUser = await driversCollection.findOne({ email: 'amit.singh@abrafleet.com' });
      const isValid = await bcrypt.compare(newPassword, updatedUser.password);
      
      console.log('🔍 Verification test:');
      console.log('Password comparison result:', isValid ? '✅ VALID' : '❌ INVALID');
    } else {
      console.log('⚠️ No changes made');
    }

  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await mongoose.connection.close();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

setAmitSinghPassword();
