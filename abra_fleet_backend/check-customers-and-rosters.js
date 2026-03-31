const { MongoClient } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkCustomersAndRosters() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abraFleet');
    
    // Check customers
    const totalCustomers = await db.collection('customers').countDocuments();
    console.log(`👥 Total customers in database: ${totalCustomers}\n`);
    
    if (totalCustomers > 0) {
      console.log('📋 Sample customers (first 10):');
      const customers = await db.collection('customers').find().limit(10).toArray();
      
      customers.forEach((customer, index) => {
        console.log(`\n   ${index + 1}. ${customer.name || 'Unknown'}`);
        console.log(`      ID: ${customer._id}`);
        console.log(`      Email: ${customer.email || 'N/A'}`);
        console.log(`      Organization: ${customer.organization || customer.organizationName || 'N/A'}`);
        console.log(`      Status: ${customer.status || 'N/A'}`);
      });
    }
    
    // Check rosters collection
    console.log('\n' + '='.repeat(80));
    const totalRosters = await db.collection('rosters').countDocuments();
    console.log(`\n📋 Total rosters in database: ${totalRosters}`);
    
    // Check if rosters collection exists
    const collections = await db.listCollections().toArray();
    const hasRostersCollection = collections.some(col => col.name === 'rosters');
    console.log(`📦 Rosters collection exists: ${hasRostersCollection ? 'YES' : 'NO'}`);
    
    // Check users collection for customers
    console.log('\n' + '='.repeat(80));
    const customerUsers = await db.collection('users').find({ role: 'customer' }).limit(10).toArray();
    console.log(`\n👤 Customer users (first 10):`);
    
    customerUsers.forEach((user, index) => {
      console.log(`\n   ${index + 1}. ${user.name || 'Unknown'}`);
      console.log(`      ID: ${user._id}`);
      console.log(`      Email: ${user.email || 'N/A'}`);
      console.log(`      UID: ${user.uid || 'N/A'}`);
    });
    
    // Check if there are any pending assignments in customers collection
    console.log('\n' + '='.repeat(80));
    console.log('\n🔍 Checking if customers have roster data embedded:');
    
    const customersWithRosterData = await db.collection('customers').find({
      $or: [
        { 'roster': { $exists: true } },
        { 'rosters': { $exists: true } },
        { 'rosterDetails': { $exists: true } }
      ]
    }).limit(5).toArray();
    
    if (customersWithRosterData.length > 0) {
      console.log(`\n✅ Found ${customersWithRosterData.length} customers with roster data:`);
      customersWithRosterData.forEach((customer, index) => {
        console.log(`\n   ${index + 1}. ${customer.name}`);
        console.log(`      Has roster field: ${customer.roster ? 'YES' : 'NO'}`);
        console.log(`      Has rosters field: ${customer.rosters ? 'YES' : 'NO'}`);
        console.log(`      Has rosterDetails field: ${customer.rosterDetails ? 'YES' : 'NO'}`);
      });
    } else {
      console.log('\n❌ No customers have embedded roster data');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n💡 DIAGNOSIS:');
    console.log('   The frontend is sending roster IDs that do not exist in the database.');
    console.log('   This could mean:');
    console.log('   1. Rosters were deleted or cleaned up');
    console.log('   2. The frontend is using old/cached roster IDs');
    console.log('   3. Rosters need to be created from customers first');
    console.log('   4. The pending_rosters screen is showing stale data');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkCustomersAndRosters();
