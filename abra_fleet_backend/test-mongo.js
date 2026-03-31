const mongoose = require('mongoose');
require('dotenv').config();

async function testConnection() {
  try {
    console.log('Testing MongoDB connection...');
    console.log('URI:', process.env.MONGODB_URI ? 'SET' : 'NOT SET');
    
    await mongoose.connect(process.env.MONGODB_URI, {
      serverSelectionTimeoutMS: 30000,
      family: 4
    });
    
    console.log('✅ Connected! ReadyState:', mongoose.connection.readyState);
    console.log('✅ DB Name:', mongoose.connection.db.databaseName);
    
    await mongoose.disconnect();
    console.log('✅ Test successful');
    process.exit(0);
  } catch (error) {
    console.error('❌ Connection failed:', error.message);
    process.exit(1);
  }
}

testConnection();