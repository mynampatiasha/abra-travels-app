const mongoose = require('mongoose');
require('dotenv').config();

// MongoDB connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function findVikramUser() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    console.log('URI:', MONGODB_URI);
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    // Get all collections
    const collections = await mongoose.connection.db.listCollections().toArray();
    console.log('\n📋 Available collections:');
    collections.forEach(col => console.log('  -', col.name));

    // Search in users collection
    console.log('\n🔍 Searching for Vikram in users collection...');
    const User = mongoose.connection.db.collection('users');
    const vikramUsers = await User.find({ 
      email: { $regex: /vikram/i } 
    }).toArray();
    
    console.log(`Found ${vikramUsers.length} users with "vikram" in email:`);
    vikramUsers.forEach(user => {
      console.log('\n📧 User found:');
      console.log('  _id:', user._id);
      console.log('  Email:', user.email);
      console.log('  Name:', user.name);
      console.log('  Role:', user.role);
      console.log('  Customer ID:', user.customerId);
      console.log('  Has Password:', !!user.password);
    });

    // Also search by name
    console.log('\n🔍 Searching by name "Vikram Singh"...');
    const byName = await User.find({ 
      name: { $regex: /vikram/i } 
    }).toArray();
    
    console.log(`Found ${byName.length} users with "vikram" in name:`);
    byName.forEach(user => {
      console.log('\n👤 User found:');
      console.log('  _id:', user._id);
      console.log('  Email:', user.email);
      console.log('  Name:', user.name);
      console.log('  Role:', user.role);
    });

    await mongoose.connection.close();
    console.log('\n✅ Database connection closed');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

findVikramUser();
