// Delete test rosters and check for real production rosters
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function deleteTestRostersAndCheckReal() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    const driverId = 'AMATisPyRgQc39FXypD4iu7unVs1';
    
    console.log('\n🗑️  Deleting test rosters created today...');
    
    // Delete the test rosters (created by setup-asha-route-data.js)
    const deleteResult = await db.collection('rosters').deleteMany({
      driverId: driverId,
      customerEmail: { $in: [
        'sarah.kumar@wipro.com',
        'mike.rahman@wipro.com',
        'priya.sharma@wipro.com',
        'raj.patel@wipro.com'
      ]}
    });
    
    console.log(`✅ Deleted ${deleteResult.deletedCount} test rosters`);
    
    // Also delete test customers
    console.log('\n🗑️  Deleting test customers...');
    const deleteCustomers = await db.collection('customers').deleteMany({
      email: { $in: [
        'sarah.kumar@wipro.com',
        'mike.rahman@wipro.com',
        'priya.sharma@wipro.com',
        'raj.patel@wipro.com'
      ]}
    });
    
    console.log(`✅ Deleted ${deleteCustomers.deletedCount} test customers`);
    
    // Now check for ANY remaining rosters for this driver
    console.log('\n🔍 Checking for REAL rosters...');
    
    const realRosters = await db.collection('rosters').find({
      driverId: driverId
    }).toArray();
    
    console.log(`\n📋 Found ${realRosters.length} REAL rosters for this driver`);
    
    if (realRosters.length === 0) {
      console.log('\n' + '='.repeat(80));
      console.log('❌ NO REAL ROSTERS FOUND!');
      console.log('='.repeat(80));
      console.log('\nThis driver has NO rosters assigned in the production database.');
      console.log('\n📝 TO FIX THIS:');
      console.log('   1. Login to admin panel');
      console.log('   2. Go to Customer Management');
      console.log('   3. Select customers');
      console.log('   4. Click "Assign Roster" or "Route Optimization"');
      console.log('   5. Select this driver: ashamynampati2003@gmail.com');
      console.log('   6. Assign vehicle and schedule');
      console.log('   7. Save');
      console.log('\n✅ Then the driver will see real rosters in their dashboard');
    } else {
      console.log('\n✅ REAL ROSTERS FOUND:');
      for (const roster of realRosters) {
        console.log(`\n  Roster ID: ${roster._id}`);
        console.log(`  Customer: ${roster.customerName || roster.customerId}`);
        console.log(`  Date: ${new Date(roster.scheduledDate).toDateString()}`);
        console.log(`  Time: ${roster.scheduledTime}`);
        console.log(`  Type: ${roster.rosterType}`);
        console.log(`  Status: ${roster.status}`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

deleteTestRostersAndCheckReal();
