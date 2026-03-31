// debug-customer-notifications.js
// Debug script to check customer notifications in database

require('dotenv').config();
const { MongoClient } = require('mongodb');

async function debugCustomerNotifications() {
  const client = await MongoClient.connect(process.env.MONGODB_URI);
  const db = client.db('abra_fleet');

  console.log('=================================================');
  console.log('🔍 CUSTOMER NOTIFICATIONS DEBUG');
  console.log('=================================================\n');

  // 1. Check total notifications
  const totalNotifications = await db.collection('notifications').countDocuments();
  console.log('1️⃣ TOTAL NOTIFICATIONS IN DATABASE:', totalNotifications);

  // 2. Check sample notification structure
  const sampleNotif = await db.collection('notifications').findOne();
  console.log('\n2️⃣ SAMPLE NOTIFICATION STRUCTURE:');
  if (sampleNotif) {
    console.log(JSON.stringify(sampleNotif, null, 2));
  } else {
    console.log('   ⚠️ No notifications found in database');
  }

  // 3. Check notifications by userRole
  const byUserRole = await db.collection('notifications').aggregate([
    { $group: { _id: '$userRole', count: { $sum: 1 } } }
  ]).toArray();
  console.log('\n3️⃣ NOTIFICATIONS BY USER ROLE:');
  byUserRole.forEach(role => {
    console.log(`   - ${role._id || 'null'}: ${role.count}`);
  });

  // 4. Check notifications by type
  const byType = await db.collection('notifications').aggregate([
    { $group: { _id: '$type', count: { $sum: 1 } } },
    { $sort: { count: -1 } }
  ]).toArray();
  console.log('\n4️⃣ NOTIFICATIONS BY TYPE:');
  byType.forEach(type => {
    console.log(`   - ${type._id || 'null'}: ${type.count}`);
  });

  // 5. Check for customer role notifications
  const customerNotifications = await db.collection('notifications')
    .find({ userRole: 'customer' })
    .limit(5)
    .toArray();
  console.log('\n5️⃣ CUSTOMER ROLE NOTIFICATIONS (first 5):');
  console.log(`   Found: ${customerNotifications.length}`);
  customerNotifications.forEach((notif, index) => {
    console.log(`\n   ${index + 1}. ${notif.title}`);
    console.log(`      - Type: ${notif.type}`);
    console.log(`      - UserId: ${notif.userId}`);
    console.log(`      - UserRole: ${notif.userRole}`);
    console.log(`      - Created: ${notif.createdAt}`);
  });

  // 6. Check unique userIds in notifications
  const uniqueUserIds = await db.collection('notifications').distinct('userId');
  console.log('\n6️⃣ UNIQUE USER IDs IN NOTIFICATIONS:');
  console.log(`   Total unique users: ${uniqueUserIds.length}`);
  console.log(`   Sample userIds:`, uniqueUserIds.slice(0, 10));

  // 7. Check users collection for customer role
  const customers = await db.collection('users')
    .find({ role: 'customer' })
    .limit(5)
    .toArray();
  console.log('\n7️⃣ CUSTOMERS IN USERS COLLECTION (first 5):');
  console.log(`   Found: ${customers.length}`);
  customers.forEach((customer, index) => {
    console.log(`\n   ${index + 1}. ${customer.name || customer.email}`);
    console.log(`      - ID: ${customer._id}`);
    console.log(`      - Email: ${customer.email}`);
    console.log(`      - Role: ${customer.role}`);
  });

  // 8. Check if any customer has notifications
  if (customers.length > 0) {
    const firstCustomerId = customers[0]._id.toString();
    console.log(`\n8️⃣ CHECKING NOTIFICATIONS FOR FIRST CUSTOMER (${firstCustomerId}):`);
    
    const customerNotifs = await db.collection('notifications')
      .find({ userId: firstCustomerId })
      .toArray();
    console.log(`   Found ${customerNotifs.length} notifications`);
    
    if (customerNotifs.length > 0) {
      console.log('\n   Sample notification:');
      console.log(JSON.stringify(customerNotifs[0], null, 2));
    }
  }

  // 9. Check customer notification types that exist
  const customerNotifTypes = await db.collection('notifications')
    .find({ userRole: 'customer' })
    .distinct('type');
  console.log('\n9️⃣ CUSTOMER NOTIFICATION TYPES IN DATABASE:');
  console.log(`   Types found: ${customerNotifTypes.length}`);
  customerNotifTypes.forEach(type => {
    console.log(`   - ${type}`);
  });

  // 10. Expected customer notification types from frontend
  const expectedTypes = [
    'route_assigned', 'roster_assigned', 'roster_assignment_updated',
    'leave_approved', 'leave_rejected', 'trip_updated', 'trip_cancelled',
    'pickup_reminder', 'address_change_approved', 'address_change_rejected',
    'trip_assigned', 'trip_started', 'eta_15min', 'eta_5min',
    'driver_arrived', 'trip_delayed', 'trip_completed', 'feedback_reply'
  ];
  
  console.log('\n🔟 EXPECTED VS ACTUAL CUSTOMER NOTIFICATION TYPES:');
  console.log(`   Expected types: ${expectedTypes.length}`);
  console.log(`   Actual types in DB: ${customerNotifTypes.length}`);
  
  const missingTypes = expectedTypes.filter(type => !customerNotifTypes.includes(type));
  if (missingTypes.length > 0) {
    console.log('\n   ⚠️ Missing types in database:');
    missingTypes.forEach(type => console.log(`      - ${type}`));
  }
  
  const extraTypes = customerNotifTypes.filter(type => !expectedTypes.includes(type));
  if (extraTypes.length > 0) {
    console.log('\n   ℹ️ Extra types in database (not filtered by frontend):');
    extraTypes.forEach(type => console.log(`      - ${type}`));
  }

  console.log('\n=================================================');
  console.log('✅ DEBUG COMPLETE');
  console.log('=================================================\n');

  await client.close();
}

debugCustomerNotifications().catch(console.error);
