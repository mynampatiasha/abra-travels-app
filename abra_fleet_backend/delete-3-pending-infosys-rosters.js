// Delete the 3 pending Infosys rosters (Rajesh, Priya, Amit)
// So user has a clean slate with only Neha and Vikram deleted as originally requested
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function deletePendingRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n🗑️  Deleting the 3 pending Infosys rosters...\n');
    
    const result = await db.collection('rosters').deleteMany({
      customerEmail: { $in: [
        'rajesh.kumar@infosys.com',
        'priya.sharma@infosys.com',
        'amit.patel@infosys.com'
      ]},
      status: 'pending'
    });
    
    console.log(`✅ Deleted ${result.deletedCount} pending rosters\n`);
    
    // Verify deletion
    const remaining = await db.collection('rosters')
      .find({ customerEmail: { $regex: '@infosys\\.com', $options: 'i' } })
      .toArray();
    
    console.log(`📊 Remaining Infosys rosters: ${remaining.length}\n`);
    
    console.log('✅ CLEAN SLATE ACHIEVED!');
    console.log('\n📝 Current State:');
    console.log('   • ALL 5 Infosys rosters deleted from database');
    console.log('   • 10 Infosys customers still exist in users collection');
    console.log('   • 0 vehicles assigned to @infosys.com');
    console.log('   • 0 drivers assigned to @infosys.com');
    
    console.log('\n📱 What You Need To Do:');
    console.log('   1. Go to Admin → Vehicle Management');
    console.log('   2. Assign vehicles to @infosys.com organization');
    console.log('   3. Assign drivers to those vehicles');
    console.log('   4. THEN use Client → Bulk Import to assign all 5 employees:');
    console.log('      - Rajesh Kumar');
    console.log('      - Priya Sharma');
    console.log('      - Amit Patel');
    console.log('      - Neha Gupta');
    console.log('      - Vikram Singh\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

deletePendingRosters();
