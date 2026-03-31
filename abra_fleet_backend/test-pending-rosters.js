// Script to delete all rosters (use with caution!)
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abrafleet';

async function deleteAllRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const rostersCollection = db.collection('rosters');
    
    // Count rosters before deletion
    const count = await rostersCollection.countDocuments();
    console.log(`\n📊 Found ${count} rosters in database`);
    
    if (count === 0) {
      console.log('✅ No rosters to delete');
      return;
    }
    
    // Show sample rosters
    const sampleRosters = await rostersCollection.find().limit(5).toArray();
    console.log('\n📋 Sample rosters to be deleted:');
    sampleRosters.forEach((roster, index) => {
      console.log(`   ${index + 1}. ${roster.customerName || 'Unknown'} - ${roster.officeLocation || 'N/A'}`);
    });
    
    // Delete all rosters
    console.log('\n🗑️  Deleting all rosters...');
    const result = await rostersCollection.deleteMany({});
    
    console.log(`\n✅ Deleted ${result.deletedCount} rosters`);
    console.log('✅ Database is now clean - ready for new rosters with coordinates');
    
    // Verify
    const remainingCount = await rostersCollection.countDocuments();
    console.log(`\n📊 Remaining rosters: ${remainingCount}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Disconnected from MongoDB');
  }
}

console.log('⚠️  WARNING: This will delete ALL rosters from the database!');
console.log('⚠️  Make sure this is what you want to do.');
console.log('\nStarting deletion in 2 seconds...\n');

setTimeout(() => {
  deleteAllRosters();
}, 2000);