const mongoose = require('mongoose');
require('dotenv').config();

async function run() {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet');
    const db = mongoose.connection.db;
    
    const drivers = await db.collection('drivers').find({}).toArray();
    
    let rajeshId, naveenId, deepakId;
    
    for (const d of drivers) {
      const name = d.personalInfo?.name || d.name || '';
      const hasEmail = d.personalInfo?.email || d.email;
      
      if (name.toLowerCase().includes('rajesh') && hasEmail) rajeshId = d._id;
      if (name.toLowerCase().includes('naveen') && hasEmail) naveenId = d._id;
      if (name.toLowerCase().includes('deepak') && hasEmail) deepakId = d._id;
    }
    
    const keepIds = [rajeshId, naveenId, deepakId].filter(id => id);
    console.log('Keeping IDs:', keepIds);
    
    if (keepIds.length === 3) {
      const result = await db.collection('drivers').deleteMany({
        _id: { $nin: keepIds }
      });
      console.log('Deleted bad drivers:', result.deletedCount);
    } else {
      console.log('Could not find all 3 perfect records!');
    }
    
    process.exit(0);
  } catch(e) {
    console.error(e);
    process.exit(1);
  }
}
run();
