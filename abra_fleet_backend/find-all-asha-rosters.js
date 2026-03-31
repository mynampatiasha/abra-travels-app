// Find ALL rosters for Asha driver using multiple search methods
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function findAllAshaRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    const searchTerms = [
      'AMATisPyRgQc39FXypD4iu7unVs1', // Firebase UID
      'ashamynampati2003@gmail.com',   // Email
      'asha',                          // Name (lowercase)
      'Asha',                          // Name (capitalized)
      'Asha Mynampati'                 // Full name
    ];
    
    console.log('\n🔍 Searching for rosters with multiple criteria...\n');
    
    let allRosters = [];
    
    // Search by driverId
    console.log('1. Searching by driverId (Firebase UID)...');
    const byDriverId = await db.collection('rosters').find({
      driverId: 'AMATisPyRgQc39FXypD4iu7unVs1'
    }).toArray();
    console.log(`   Found: ${byDriverId.length} rosters`);
    allRosters.push(...byDriverId);
    
    // Search by driverEmail
    console.log('\n2. Searching by driverEmail...');
    const byEmail = await db.collection('rosters').find({
      driverEmail: 'ashamynampati2003@gmail.com'
    }).toArray();
    console.log(`   Found: ${byEmail.length} rosters`);
    allRosters.push(...byEmail);
    
    // Search by driverName (case insensitive)
    console.log('\n3. Searching by driverName...');
    const byName = await db.collection('rosters').find({
      driverName: { $regex: /asha/i }
    }).toArray();
    console.log(`   Found: ${byName.length} rosters`);
    allRosters.push(...byName);
    
    // Search by driver field (if it's an object)
    console.log('\n4. Searching by driver.email...');
    const byDriverObject = await db.collection('rosters').find({
      'driver.email': 'ashamynampati2003@gmail.com'
    }).toArray();
    console.log(`   Found: ${byDriverObject.length} rosters`);
    allRosters.push(...byDriverObject);
    
    // Search by driver.uid
    console.log('\n5. Searching by driver.uid...');
    const byDriverUid = await db.collection('rosters').find({
      'driver.uid': 'AMATisPyRgQc39FXypD4iu7unVs1'
    }).toArray();
    console.log(`   Found: ${byDriverUid.length} rosters`);
    allRosters.push(...byDriverUid);
    
    // Remove duplicates
    const uniqueRosters = Array.from(new Map(allRosters.map(r => [r._id.toString(), r])).values());
    
    console.log('\n' + '='.repeat(80));
    console.log(`📋 TOTAL UNIQUE ROSTERS FOUND: ${uniqueRosters.length}`);
    console.log('='.repeat(80));
    
    if (uniqueRosters.length === 0) {
      console.log('\n❌ NO ROSTERS FOUND for Asha driver!');
      console.log('\n🔍 Let me check the driver record...');
      
      const driver = await db.collection('drivers').findOne({
        email: 'ashamynampati2003@gmail.com'
      });
      
      if (driver) {
        console.log('\n✅ Driver record found:');
        console.log(JSON.stringify(driver, null, 2));
      } else {
        console.log('\n❌ Driver record NOT found!');
      }
      
      console.log('\n🔍 Let me check ALL rosters to see what driver IDs exist...');
      const allRostersInDb = await db.collection('rosters').find({}).limit(10).toArray();
      console.log(`\nSample of ${allRostersInDb.length} rosters:`);
      for (const roster of allRostersInDb) {
        console.log(`\n  Roster ID: ${roster._id}`);
        console.log(`  driverId: ${roster.driverId || 'N/A'}`);
        console.log(`  driverEmail: ${roster.driverEmail || 'N/A'}`);
        console.log(`  driverName: ${roster.driverName || 'N/A'}`);
        console.log(`  driver object: ${roster.driver ? JSON.stringify(roster.driver) : 'N/A'}`);
        console.log(`  scheduledDate: ${roster.scheduledDate}`);
      }
      
    } else {
      console.log('\n✅ ROSTERS FOUND! Details:\n');
      
      // Group by date
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      
      const todayRosters = [];
      const pastRosters = [];
      const futureRosters = [];
      
      for (const roster of uniqueRosters) {
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
      
      console.log('📅 TODAY:', todayRosters.length);
      console.log('📅 PAST:', pastRosters.length);
      console.log('📅 FUTURE:', futureRosters.length);
      
      if (todayRosters.length > 0) {
        console.log('\n' + '='.repeat(80));
        console.log('📅 TODAY\'S ROSTERS');
        console.log('='.repeat(80));
        for (const roster of todayRosters) {
          console.log(`\n  Roster ID: ${roster._id}`);
          console.log(`  Customer: ${roster.customerName || roster.customerId}`);
          console.log(`  Email: ${roster.customerEmail || 'N/A'}`);
          console.log(`  Phone: ${roster.customerPhone || 'N/A'}`);
          console.log(`  Type: ${roster.rosterType}`);
          console.log(`  Time: ${roster.scheduledTime}`);
          console.log(`  Status: ${roster.status}`);
          console.log(`  Pickup: ${roster.pickupLocation || roster.loginPickupAddress || 'N/A'}`);
          console.log(`  Drop: ${roster.dropLocation || roster.officeLocation || 'N/A'}`);
          console.log(`  Vehicle: ${roster.vehicleId || 'N/A'}`);
        }
      }
      
      if (pastRosters.length > 0) {
        console.log('\n' + '='.repeat(80));
        console.log('📅 PAST ROSTERS (Last 5)');
        console.log('='.repeat(80));
        for (const roster of pastRosters.slice(0, 5)) {
          const date = new Date(roster.scheduledDate);
          console.log(`\n  ${date.toDateString()} - ${roster.rosterType} - ${roster.customerName || roster.customerId}`);
        }
      }
      
      if (futureRosters.length > 0) {
        console.log('\n' + '='.repeat(80));
        console.log('📅 FUTURE ROSTERS (Next 5)');
        console.log('='.repeat(80));
        for (const roster of futureRosters.slice(0, 5)) {
          const date = new Date(roster.scheduledDate);
          console.log(`\n  ${date.toDateString()} - ${roster.rosterType} - ${roster.customerName || roster.customerId}`);
        }
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

findAllAshaRosters();
