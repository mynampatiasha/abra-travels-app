// Delete Infosys rosters from MongoDB Atlas
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function deleteInfosysRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 Finding all Infosys rosters...\n');
    
    // Find all rosters with Infosys emails
    const rosters = await db.collection('rosters')
      .find({
        customerEmail: { $regex: '@infosys\\.com$', $options: 'i' }
      })
      .toArray();
    
    console.log(`📊 Found ${rosters.length} Infosys rosters\n`);
    
    if (rosters.length === 0) {
      console.log('✅ No Infosys rosters to delete');
      return;
    }
    
    // Display rosters
    console.log('📋 Rosters to be deleted:');
    rosters.forEach((roster, index) => {
      console.log(`\n${index + 1}. ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName} (${roster.customerEmail})`);
      console.log(`   Vehicle: ${roster.vehicleNumber || 'N/A'}`);
      console.log(`   Driver: ${roster.driverName || 'N/A'}`);
      console.log(`   Status: ${roster.status}`);
    });
    
    console.log('\n⚠️  Deleting rosters...\n');
    
    // Delete all Infosys rosters
    const result = await db.collection('rosters').deleteMany({
      customerEmail: { $regex: '@infosys\\.com$', $options: 'i' }
    });
    
    console.log(`✅ Successfully deleted ${result.deletedCount} rosters!`);
    console.log('\n📝 Next Steps:');
    console.log('   1. Refresh the Client Roster Management page');
    console.log('   2. The rosters will disappear from Active Rosters');
    console.log('   3. Dashboard counts will update to 0');
    console.log('   4. You can now reassign these employees via bulk import\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('✅ MongoDB connection closed');
  }
}

deleteInfosysRosters();
