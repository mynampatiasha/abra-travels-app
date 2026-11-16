const mongoose = require('mongoose');
require('dotenv').config();

async function run() {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet');
    const db = mongoose.connection.db;
    
    // Delete any drivers that do not have personalInfo (the N/A ones)
    const result = await db.collection('drivers').deleteMany({
      personalInfo: { $exists: false }
    });
    
    console.log('Deleted bad drivers (no personalInfo):', result.deletedCount);
    
    // Also delete any users that correspond to these deleted drivers
    const validDrivers = await db.collection('drivers').find({}).toArray();
    const validEmails = validDrivers.map(d => d.personalInfo?.email || d.email).filter(e => e);
    
    const userResult = await db.collection('users').deleteMany({
      role: 'driver',
      email: { $nin: validEmails }
    });
    console.log('Deleted orphaned users:', userResult.deletedCount);
    
    process.exit(0);
  } catch(e) {
    console.error(e);
    process.exit(1);
  }
}
run();
