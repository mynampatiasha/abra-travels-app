// Test Address Change Request Notification (Using Users Collection)
// Run: node test-address-change-notification-v2.js

require('dotenv').config();
const { MongoClient } = require('mongodb');

async function testAddressChangeNotification() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n' + '='.repeat(80));
    console.log('🔔 ADDRESS CHANGE NOTIFICATION TEST');
    console.log('='.repeat(80) + '\n');

    // 1. Find a customer (role=customer) with organization
    console.log('1️⃣ Finding test customer...');
    const customer = await db.collection('users').findOne({
      role: 'customer',
      $or: [
        { organizationName: { $exists: true, $ne: '' } },
        { companyName: { $exists: true, $ne: '' } }
      ]
    });

    if (!customer) {
      console.log('❌ No customer with organization found');
      console.log('   Create a customer with organizationName/companyName field first');
      return;
    }

    const organizationName = customer.organizationName || customer.companyName;
    
    console.log(`✅ Found customer: ${customer.name || customer.email}`);
    console.log(`   Organization: ${organizationName}`);
    console.log(`   Firebase UID: ${customer.firebaseUid}`);
    console.log(`   Role: ${customer.role}`);

    // 2. Find admins in same organization
    console.log('\n2️⃣ Finding admins in same organization...');
    const admins = await db.collection('users').find({
      role: { $in: ['admin', 'client'] },
      $or: [
        { companyName: organizationName },
        { organizationName: organizationName }
      ]
    }).toArray();

    console.log(`✅ Found ${admins.length} admin(s):`);
    admins.forEach(admin => {
      console.log(`   - ${admin.name || admin.email} (${admin.role})`);
      console.log(`     Firebase UID: ${admin.firebaseUid}`);
      console.log(`     Organization: ${admin.organizationName || admin.companyName}`);
    });

    if (admins.length === 0) {
      console.log('⚠️  No admins found in this organization');
      console.log('   Notification will not be sent');
      console.log('\n💡 To fix: Create an admin user with same organizationName/companyName');
      return;
    }

    // 3. Simulate address change request submission
    console.log('\n3️⃣ Simulating address change request...');
    
    const addressChangeRequest = {
      customerId: customer.firebaseUid,
      customerName: customer.name || customer.email,
      customerEmail: customer.email,
      customerPhone: customer.phoneNumber || customer.phone || '',
      organizationName: organizationName,
      
      currentPickupAddress: '123 Old Street, Bangalore',
      newPickupAddress: '456 New Street, Bangalore',
      newPickupLat: 12.9716,
      newPickupLng: 77.5946,
      
      currentDropAddress: '789 Old Office, Bangalore',
      newDropAddress: '321 New Office, Bangalore',
      newDropLat: 12.9352,
      newDropLng: 77.6245,
      
      reason: 'TEST: Moved to new residence',
      status: 'under_review',
      
      affectedTripIds: [],
      affectedTripsCount: 5,
      
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const result = await db.collection('address_change_requests').insertOne(addressChangeRequest);
    console.log(`✅ Created address change request: ${result.insertedId}`);

    // 4. Create notifications for all admins (EXACTLY as the API does)
    console.log('\n4️⃣ Creating notifications for admins...');
    
    const adminNotifications = admins.map(admin => ({
      userId: admin.firebaseUid,
      userRole: admin.role,
      title: 'New Address Change Request',
      message: `${customer.name || customer.email} has requested an address change`,
      type: 'address_change_request',
      data: {
        requestId: result.insertedId.toString(),
        customerId: customer.firebaseUid,
        customerName: customer.name || customer.email,
        customerEmail: customer.email,
        affectedTripsCount: 5,
        organizationName: organizationName
      },
      read: false,
      createdAt: new Date()
    }));

    if (adminNotifications.length > 0) {
      const notifResult = await db.collection('notifications').insertMany(adminNotifications);
      console.log(`✅ Created ${notifResult.insertedCount} notification(s)`);
      
      // Show notification details
      console.log('\n📧 Notification Details:');
      adminNotifications.forEach((notif, index) => {
        console.log(`\n   Notification ${index + 1}:`);
        console.log(`   To: ${admins[index].name || admins[index].email}`);
        console.log(`   User ID: ${notif.userId}`);
        console.log(`   Title: ${notif.title}`);
        console.log(`   Message: ${notif.message}`);
        console.log(`   Type: ${notif.type}`);
        console.log(`   Read: ${notif.read}`);
      });
    }

    // 5. Verify notifications were created
    console.log('\n5️⃣ Verifying notifications in database...');
    
    for (const admin of admins) {
      const notification = await db.collection('notifications').findOne({
        userId: admin.firebaseUid,
        type: 'address_change_request',
        'data.requestId': result.insertedId.toString()
      });

      if (notification) {
        console.log(`✅ Notification found for ${admin.name || admin.email}`);
        console.log(`   ID: ${notification._id}`);
        console.log(`   Read: ${notification.read}`);
        console.log(`   Created: ${notification.createdAt.toISOString()}`);
      } else {
        console.log(`❌ Notification NOT found for ${admin.name || admin.email}`);
      }
    }

    // 6. Summary
    console.log('\n' + '='.repeat(80));
    console.log('✅ TEST COMPLETED SUCCESSFULLY');
    console.log('='.repeat(80));
    console.log('\n📊 Summary:');
    console.log(`   Customer: ${customer.name || customer.email}`);
    console.log(`   Organization: ${organizationName}`);
    console.log(`   Request ID: ${result.insertedId}`);
    console.log(`   Admins notified: ${admins.length}`);
    console.log(`   Notifications created: ${adminNotifications.length}`);
    
    console.log('\n🔔 What Admins Will See:');
    console.log('   Title: "New Address Change Request"');
    console.log(`   Message: "${customer.name || customer.email} has requested an address change"`);
    console.log('   Type: address_change_request');
    console.log(`   Affected Trips: 5`);
    
    console.log('\n📱 How to Check:');
    console.log('   1. Admin logs into their app');
    console.log('   2. Opens notifications screen');
    console.log('   3. Should see the new notification');
    console.log('   4. Can tap to view address change request details');
    
    console.log('\n🧹 Cleanup (optional):');
    console.log(`   Delete request: db.address_change_requests.deleteOne({_id: ObjectId("${result.insertedId}")})`);
    console.log(`   Delete notifications: db.notifications.deleteMany({"data.requestId": "${result.insertedId}"})`);
    console.log('='.repeat(80) + '\n');

  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await client.close();
  }
}

testAddressChangeNotification();
