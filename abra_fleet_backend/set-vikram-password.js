const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

// MongoDB connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

// User model - matching the actual schema from the database
const userSchema = new mongoose.Schema({
  customerId: String,
  name: String,
  email: String,
  phone: String,
  companyName: String,
  department: String,
  branch: String,
  employeeId: String,
  status: String,
  role: String,
  firebaseUid: String,
  password: String,
  resetToken: String,
  resetTokenExpires: Date,
  createdAt: Date,
  updatedAt: Date,
  createdBy: String
}, { collection: 'customers' });

const User = mongoose.model('Customer', userSchema);

async function setVikramPassword() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    // Find user by email
    const user = await User.findOne({ email: 'vikram.singh@abrafleet.com' });
    
    if (!user) {
      console.log('❌ User vikram.singh@abrafleet.com not found');
      console.log('\n📋 Checking all users with similar email...');
      const similarUsers = await User.find({ 
        email: { $regex: /vikram/i } 
      }).select('email name role');
      console.log('Similar users:', similarUsers);
      process.exit(1);
    }

    console.log('\n📋 Current user details:');
    console.log('Email:', user.email);
    console.log('Name:', user.name);
    console.log('Role:', user.role);
    console.log('Customer ID:', user.customerId);
    console.log('Employee ID:', user.employeeId);
    console.log('Company:', user.companyName);
    console.log('Department:', user.department);

    // Hash the new password
    const newPassword = 'abrafleet123';
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    // Update password
    user.password = hashedPassword;
    await user.save();

    console.log('\n✅ Password updated successfully!');
    console.log('📧 Email: vikram.singh@abrafleet.com');
    console.log('🔑 New Password: abrafleet123');
    
    // Verify the password works
    const isMatch = await bcrypt.compare(newPassword, user.password);
    console.log('\n🔍 Password verification:', isMatch ? '✅ SUCCESS' : '❌ FAILED');

    await mongoose.connection.close();
    console.log('\n✅ Database connection closed');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

setVikramPassword();
