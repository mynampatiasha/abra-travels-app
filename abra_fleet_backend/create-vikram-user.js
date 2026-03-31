const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

// MongoDB connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

// User model
const userSchema = new mongoose.Schema({
  email: String,
  password: String,
  name: String,
  role: String,
  organizationId: String,
  phoneNumber: String,
  isActive: Boolean,
  createdAt: Date
}, { collection: 'users' });

const User = mongoose.model('User', userSchema);

async function createVikramUser() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    // Check if user already exists
    let user = await User.findOne({ email: 'vikram.singh@abrafleet.com' });
    
    if (user) {
      console.log('📋 User already exists, updating password...');
    } else {
      console.log('📋 Creating new user...');
      user = new User({
        email: 'vikram.singh@abrafleet.com',
        name: 'Vikram Singh',
        role: 'driver',
        phoneNumber: '+919876543210',
        isActive: true,
        createdAt: new Date(),
        organizationId: 'abrafleet_org_001' // Default organization
      });
    }

    // Hash the password
    const newPassword = 'abrafleet123';
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    // Update password
    user.password = hashedPassword;
    await user.save();

    console.log('\n✅ User created/updated successfully!');
    console.log('📧 Email: vikram.singh@abrafleet.com');
    console.log('🔑 Password: abrafleet123');
    console.log('👤 Name:', user.name);
    console.log('🎭 Role:', user.role);
    console.log('🏢 Organization ID:', user.organizationId);
    console.log('📱 Phone:', user.phoneNumber);
    
    // Verify the password works
    const isMatch = await bcrypt.compare(newPassword, user.password);
    console.log('\n🔍 Password verification:', isMatch ? '✅ SUCCESS' : '❌ FAILED');

    await mongoose.connection.close();
    console.log('\n✅ Database connection closed');
    console.log('\n🎉 You can now login with:');
    console.log('   Email: vikram.singh@abrafleet.com');
    console.log('   Password: abrafleet123');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

createVikramUser();
