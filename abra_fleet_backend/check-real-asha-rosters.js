// Check for real rosters assigned to Asha driver
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkRealAshaRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    const driverId = 'AMATisPyRgQc39FXypD4iu7unVs1';
    
    console.log('\n🔍 Checking ALL rosters for driver:', driverId);
    console.log('   Email: ashamynampati2003@gmail.com');
    
    // Get ALL rosters for this driver (not just today)
    const allRosters = await db.collection('rosters').find({
      driverId: driverId
    }).sort({ scheduledDate: -1 }).toArray();
    
    console.log(`\n📋 Found ${allRosters.length} total rosters for this driver`);
    
    if (allRosters.length === 0) {
      console.log('\n❌ NO ROSTERS FOUND!');
      console.log('   This driver has no rosters assigned in the database.');
      console.log('   You need to assign rosters through the admin panel first.');
      return;
    }
    
    // Group by date
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const todayRosters = [];
    const pastRosters = [];
    const futureRosters = [];
    
    for (const roster of allRosters) {
      const rosterDate = new Date(roster.scheduledDate);
      rosterDate.setHours(0, 0, 0, 0);
      
      if (rosterDate.getTime() === today.getTime()) {
        todayRosters.push(roster);
      } else if (rosterDate < today) {
        pastRosters.push(roster);
      } else {
        futureRosters.push(roster);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📅 TODAY\'S ROSTERS:', todayRosters.length);
    console.log('='.repeat(80));
    
    if (todayRosters.length === 0) {
      console.log('❌ No rosters for today');
    } else {
      for (const roster of todayRosters) {
        console.log(`\nRoster ID: ${roster._id}`);
        console.log(`  Customer ID: ${roster.customerId}`);
        console.log(`  Customer Name: ${roster.customerName || 'N/A'}`);
        console.log(`  Customer Email: ${roster.customerEmail || 'N/A'}`);
        console.log(`  Vehicle ID: ${roster.vehicleId || 'N/A'}`);
        console.log(`  Type: ${roster.rosterType}`);
        console.log(`  Time: ${roster.scheduledTime}`);
        console.log(`  Status: ${roster.status}`);
        console.log(`  Pickup: ${roster.pickupLocation || roster.loginPickupAddress || 'N/A'}`);
        console.log(`  Drop: ${roster.dropLocation || roster.officeLocation || 'N/A'}`);
        console.log(`  Created: ${roster.createdAt}`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📅 PAST ROSTERS:', pastRosters.length);
    console.log('='.repeat(80));
    
    if (pastRosters.length > 0) {
      console.log('(Showing last 5)');
      for (const roster of pastRosters.slice(0, 5)) {
        const date = new Date(roster.scheduledDate);
        console.log(`\n${date.toDateString()} - ${roster.rosterType} - ${roster.customerName || roster.customerId}`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📅 FUTURE ROSTERS:', futureRosters.length);
    console.log('='.repeat(80));
    
    if (futureRosters.length > 0) {
      console.log('(Showing next 5)');
      for (const roster of futureRosters.slice(0, 5)) {
        const date = new Date(roster.scheduledDate);
        console.log(`\n${date.toDateString()} - ${roster.rosterType} - ${roster.customerName || roster.customerId}`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('💡 SUMMARY');
    console.log('='.repeat(80));
    console.log(`Total rosters: ${allRosters.length}`);
    console.log(`Today: ${todayRosters.length}`);
    console.log(`Past: ${pastRosters.length}`);
    console.log(`Future: ${futureRosters.length}`);
    
    if (todayRosters.length === 0) {
      console.log('\n⚠️  NO ROSTERS FOR TODAY!');
      console.log('   The driver dashboard will show "No route assigned for today"');
      console.log('   You need to assign rosters through the admin panel.');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRealAshaRosters();
