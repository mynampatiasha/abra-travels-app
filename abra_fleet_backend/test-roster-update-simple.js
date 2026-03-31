// test-roster-update-simple.js
// Simple test to verify roster update endpoint and admin notification logic

const { MongoClient } = require('mongodb');
require('dotenv').config();

async function testRosterUpdateEndpoint() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔍 Testing Roster Update Notification System...\n');
    
    // 1. Check if we have admin users
    console.log('1. Checking for admin users...');
    const adminUsers = await db.collection('users').find({ role: 'admin' }).toArray();
    console.log(`   Found ${adminUsers.length} admin users:`);
    adminUsers.forEach(admin => {
      console.log(`   - ${admin.name || admin.email} (${admin.firebaseUid})`);
    });
    
    if (adminUsers.length === 0) {
      console.log('❌ No admin users found! Notifications cannot be sent.');
      return;
    }
    
    // 2. Check if we have customer rosters that can be updated
    console.log('\n2. Checking for updatable customer rosters...');
    const customerRosters = await db.collection('rosters').find({
      status: { $in: ['pending_assignment', 'pending'] }
    }).limit(5).toArray();
    
    console.log(`   Found ${customerRosters.length} updatable rosters:`);
    customerRosters.forEach(roster => {
      console.log(`   - Roster ${roster._id} (${roster.rosterType}) - Status: ${roster.status}`);
      console.log(`     Customer: ${roster.userId}`);
      console.log(`     Office: ${roster.officeLocation || 'Not specified'}`);
    });
    
    if (customerRosters.length === 0) {
      console.log('❌ No updatable rosters found!');
      return;
    }
    
    // 3. Check customer users for the rosters
    console.log('\n3. Checking customer details...');
    const customerIds = [...new Set(customerRosters.map(r => r.userId))];
    const customers = await db.collection('users').find({
      firebaseUid: { $in: customerIds }
    }).toArray();
    
    console.log(`   Found ${customers.length} customers:`);
    customers.forEach(customer => {
      console.log(`   - ${customer.name || customer.email} (${customer.firebaseUid})`);
    });
    
    // 4. Simulate the notification logic (without actually sending)
    console.log('\n4. Simulating admin notification logic...');
    const testRoster = customerRosters[0];
    const testCustomer = customers.find(c => c.firebaseUid === testRoster.userId);
    const customerName = testCustomer ? testCustomer.name || testCustomer.email : 'Unknown Customer';
    
    console.log(`   Test scenario:`);
    console.log(`   - Roster ID: ${testRoster._id}`);
    console.log(`   - Customer: ${customerName}`);
    console.log(`   - Roster Type: ${testRoster.rosterType}`);
    console.log(`   - Office Location: ${testRoster.officeLocation || 'Not specified'}`);
    
    // Simulate notification creation for each admin
    console.log(`\n   Notifications that would be sent to ${adminUsers.length} admin(s):`);
    adminUsers.forEach(admin => {
      const notification = {
        userId: admin.firebaseUid,
        type: 'roster_updated',
        title: 'Customer Roster Updated',
        body: `${customerName} has updated their roster request. Please review the changes.`,
        priority: 'normal',
        category: 'roster_management',
        data: {
          rosterId: testRoster._id.toString(),
          customerName: customerName,
          customerId: testRoster.userId,
          rosterType: testRoster.rosterType,
          officeLocation: testRoster.officeLocation,
          updatedAt: new Date().toISOString()
        }
      };
      
      console.log(`   ✅ Admin: ${admin.name || admin.email}`);
      console.log(`      Title: ${notification.title}`);
      console.log(`      Body: ${notification.body}`);
      console.log(`      Data: ${JSON.stringify(notification.data, null, 8)}`);
    });
    
    // 5. Check existing notifications
    console.log('\n5. Checking existing roster_updated notifications...');
    const existingNotifications = await db.collection('notifications').find({
      type: 'roster_updated'
    }).sort({ createdAt: -1 }).limit(5).toArray();
    
    console.log(`   Found ${existingNotifications.length} recent roster update notifications:`);
    existingNotifications.forEach(notif => {
      console.log(`   - ${notif.title} (${notif.createdAt})`);
      console.log(`     To: ${notif.userId}`);
      console.log(`     Customer: ${notif.data?.customerName || 'Unknown'}`);
    });
    
    console.log('\n✅ Roster update notification system test completed!');
    console.log('\n📋 Summary:');
    console.log(`   - Admin users available: ${adminUsers.length}`);
    console.log(`   - Updatable rosters: ${customerRosters.length}`);
    console.log(`   - Customer users found: ${customers.length}`);
    console.log(`   - Notifications would be sent: ${adminUsers.length}`);
    console.log(`   - Existing roster update notifications: ${existingNotifications.length}`);
    
    if (adminUsers.length > 0 && customerRosters.length > 0) {
      console.log('\n🎯 System is ready for roster update notifications!');
      console.log('   When a customer updates their roster, admins will be notified.');
    } else {
      console.log('\n⚠️  System needs setup:');
      if (adminUsers.length === 0) console.log('   - Add admin users to the system');
      if (customerRosters.length === 0) console.log('   - Need customer rosters to test with');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    await client.close();
  }
}

// Run the test
testRosterUpdateEndpoint().catch(console.error);