// Check ALL assigned rosters to see which drivers have assignments
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkAllAssignedRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get today's date
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    // Find ALL rosters that have an assigned driver
    const assignedRosters = await db.collection('rosters').find({
      assignedDriver: { $ne: null },
      startDate: { $lte: today },
      endDate: { $gte: today }
    }).toArray();
    
    console.log(`\n📋 Found ${assignedRosters.length} rosters with assigned drivers for today`);
    
    // Group by driver
    const byDriver = {};
    for (const roster of assignedRosters) {
      const driverId = roster.assignedDriver;
      if (!byDriver[driverId]) {
        byDriver[driverId] = [];
      }
      byDriver[driverId].push(roster);
    }
    
    console.log(`\n👥 ${Object.keys(byDriver).length} drivers have rosters assigned\n`);
    
    // Get driver details for each
    for (const [driverId, rosters] of Object.entries(byDriver)) {
      const driver = await db.collection('drivers').findOne({
        _id: driverId
      });
      
      console.log('='.repeat(80));
      console.log(`Driver: ${driver?.name || driverId}`);
      console.log(`Email: ${driver?.email || 'N/A'}`);
      console.log(`MongoDB _id: ${driverId}`);
      console.log(`Rosters: ${rosters.length}`);
      console.log('─'.repeat(80));
      
      for (const roster of rosters.slice(0, 3)) {
        const customer = await db.collection('users').findOne({
          uid: roster.userId
        });
        
        console.log(`  • Customer: ${customer?.name || roster.userId}`);
        console.log(`    Type: ${roster.rosterType} | Status: ${roster.status}`);
        console.log(`    Time: ${roster.startTime} - ${roster.endTime}`);
        console.log(`    Office: ${roster.officeLocation}`);
      }
      
      if (rosters.length > 3) {
        console.log(`  ... and ${rosters.length - 3} more`);
      }
      console.log('');
    }
    
    // Check Asha specifically
    console.log('='.repeat(80));
    console.log('🔍 CHECKING ASHA DRIVER SPECIFICALLY');
    console.log('='.repeat(80));
    
    const ashaDriver = await db.collection('drivers').findOne({
      email: 'ashamynampati2003@gmail.com'
    });
    
    if (ashaDriver) {
      console.log(`\nAsha's MongoDB _id: ${ashaDriver._id}`);
      console.log(`Asha's Firebase UID: ${ashaDriver.uid}`);
      
      const ashaRosters = byDriver[ashaDriver._id.toString()];
      if (ashaRosters) {
        console.log(`✅ Asha HAS ${ashaRosters.length} rosters assigned!`);
      } else {
        console.log(`❌ Asha has NO rosters assigned`);
        console.log(`\n💡 Admin needs to assign rosters to Asha through the admin panel`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAllAssignedRosters();
