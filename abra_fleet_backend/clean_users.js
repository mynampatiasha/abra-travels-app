const mongoose = require('mongoose');
require('dotenv').config();

async function run() {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet');
    const db = mongoose.connection.db;
    
    // Get all valid driver emails
    const validDrivers = await db.collection('drivers').find({}).toArray();
    const validEmails = validDrivers.map(d => d.personalInfo?.email || d.email).filter(e => e);
    
    console.log('Valid emails:', validEmails);
    
    const result = await db.collection('users').deleteMany({
      role: 'driver',
      email: { $nin: validEmails }
    });
    
    console.log('Deleted orphaned driver users:', result.deletedCount);
    
    process.exit(0);
  } catch(e) {
    console.error(e);
    process.exit(1);
  }
}
run();
