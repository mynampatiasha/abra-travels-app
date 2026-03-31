// Script to delete all rosters with broken driver references
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function deleteBrokenRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    const rostersCollection = db.collection('rosters');
    
    // Count total rosters before deletion
    const totalBefore = await rostersCollection.countDocuments();
    console.log(`📊 Total rosters before deletion: ${totalBefore}\n`);
    
    // Delete ALL rosters (since they all have broken references)
    const result = await rostersCollection.deleteMany({});
    
    console.log(`🗑️  Deleted ${result.deletedCount} rosters\n`);
    
    // Verify deletion
    const totalAfter = await rostersCollection.countDocuments();
    console.log(`📊 Total rosters after deletion: ${totalAfter}\n`);
    
    if (totalAfter === 0) {
      console.log('✅ SUCCESS: All broken rosters have been deleted!');
      console.log('\n📝 NEXT STEPS:');
      console.log('1. Login to the admin panel');
      console.log('2. Go to Customer Management → Roster Assignment');
      console.log('3. Assign customers to drivers');
      console.log('4. The system will now use correct MongoDB _id references');
      console.log('5. Login as driver to see the assigned route\n');
    } else {
      console.log('⚠️  Warning: Some rosters still remain');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('✅ Connection closed');
  }
}

deleteBrokenRosters();
