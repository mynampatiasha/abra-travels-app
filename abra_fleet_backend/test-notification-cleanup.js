// Test script to verify notification cleanup after customer approval
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
  });
}

async function testNotificationCleanup() {
  console.log('\n' + '='.repeat(80));
  console.log('🧪 TESTING NOTIFICATION CLEANUP');
  console.log('='.repeat(80));

  try {
    // Step 1: Get all admin users
    console.log('\n📋 Step 1: Finding admin users...');
    const adminsSnapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'admin')
      .get();
    
    const adminIds = adminsSnapshot.docs.map(doc => doc.id);
    console.log(`✅ Found ${adminIds.length} admin users:`);
    adminIds.forEach(id => console.log(`   - ${id}`));

    // Step 2: Check notifications for each admin
    console.log('\n📋 Step 2: Checking notifications for each admin...');
    
    for (const adminId of adminIds) {
      console.log(`\n👤 Admin: ${adminId}`);
      
      const notificationsRef = admin.database().ref(`notifications/${adminId}`);
      const snapshot = await notificationsRef.once('value');
      
      if (!snapshot.exists()) {
        console.log('   ℹ️  No notifications found');
        continue;
      }

      const notifications = snapshot.val();
      const notifCount = Object.keys(notifications).length;
      console.log(`   📬 Total notifications: ${notifCount}`);

      // Count by type
      const typeCount = {};
      Object.entries(notifications).forEach(([id, notif]) => {
        const type = notif.type || 'unknown';
        typeCount[type] = (typeCount[type] || 0) + 1;
      });

      console.log('   📊 Breakdown by type:');
      Object.entries(typeCount).forEach(([type, count]) => {
        console.log(`      - ${type}: ${count}`);
      });

      // Check for customer_registration notifications
      const customerRegNotifs = Object.entries(notifications).filter(
        ([id, notif]) => notif.type === 'customer_registration'
      );

      if (customerRegNotifs.length > 0) {
        console.log(`\n   ⚠️  Found ${customerRegNotifs.length} customer_registration notifications:`);
        
        for (const [notifId, notif] of customerRegNotifs) {
          const customerId = notif.metadata?.customerId || notif.data?.customerId;
          const customerEmail = notif.metadata?.customerEmail || notif.data?.customerEmail;
          const customerName = notif.metadata?.customerName || notif.data?.customerName;
          
          console.log(`\n      📧 Notification ID: ${notifId}`);
          console.log(`         Customer ID: ${customerId || 'N/A'}`);
          console.log(`         Customer Email: ${customerEmail || 'N/A'}`);
          console.log(`         Customer Name: ${customerName || 'N/A'}`);
          console.log(`         Title: ${notif.title}`);
          console.log(`         Created: ${notif.createdAt}`);

          // Check if customer still exists and their status
          if (customerId) {
            try {
              const customerDoc = await admin.firestore()
                .collection('users')
                .doc(customerId)
                .get();

              if (customerDoc.exists) {
                const customerData = customerDoc.data();
                const status = customerData.status;
                const isPending = customerData.isPendingApproval;

                console.log(`         Customer Status: ${status}`);
                console.log(`         Pending Approval: ${isPending}`);

                if (status === 'Active' || status === 'Rejected') {
                  console.log(`         ❌ OBSOLETE: Customer already ${status}!`);
                  console.log(`         🧹 This notification should have been deleted!`);
                }
              } else {
                console.log(`         ⚠️  Customer not found in Firestore`);
              }
            } catch (err) {
              console.log(`         ⚠️  Error checking customer: ${err.message}`);
            }
          }
        }
      } else {
        console.log('   ✅ No customer_registration notifications (clean!)');
      }
    }

    // Step 3: Summary
    console.log('\n' + '='.repeat(80));
    console.log('📊 SUMMARY');
    console.log('='.repeat(80));
    console.log('✅ Test completed');
    console.log('💡 If you see obsolete notifications above, they should be cleaned up');
    console.log('💡 Run the cleanup manually or approve/reject the customers again');
    console.log('='.repeat(80) + '\n');

  } catch (error) {
    console.error('\n❌ Error:', error);
    console.error('Stack:', error.stack);
  } finally {
    process.exit(0);
  }
}

// Run the test
testNotificationCleanup();
