// test-customer-leave-notification.js
// Test script to verify customer leave request sends notification to correct client

require('dotenv').config();
const admin = require('./config/firebase');
const { MongoClient } = require('mongodb');

async function testCustomerLeaveNotification() {
  const mongoClient = new MongoClient(process.env.MONGODB_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🧪 TESTING CUSTOMER LEAVE REQUEST NOTIFICATION');
    console.log('='.repeat(80));
    
    await mongoClient.connect();
    const db = mongoClient.db('abrafleet');
    
    // Step 1: Get customer info (Asha)
    console.log('\n📋 Step 1: Getting customer information...');
    
    // Check MongoDB first
    let customer = await db.collection('users').findOne({
      email: 'asha123@cognizant.com'
    });
    
    // If not in MongoDB, check Firestore
    if (!customer) {
      console.log('   Customer not in MongoDB, checking Firestore...');
      const firestore = admin.firestore();
      const usersSnapshot = await firestore.collection('users')
        .where('email', '==', 'asha123@cognizant.com')
        .get();
      
      if (!usersSnapshot.empty) {
        const doc = usersSnapshot.docs[0];
        customer = {
          firebaseUid: doc.id,
          ...doc.data()
        };
        console.log('   ✅ Found in Firestore');
      }
    }
    
    if (!customer) {
      console.log('❌ Customer not found in MongoDB or Firestore');
      return;
    }
    
    console.log(`✅ Customer found: ${customer.name} (${customer.email})`);
    console.log(`   Organization: ${customer.companyName || customer.organizationName}`);
    console.log(`   Firebase UID: ${customer.firebaseUid}`);
    
    const customerOrg = customer.companyName || customer.organizationName;
    
    // Step 2: Find client users with matching email domain
    console.log('\n📋 Step 2: Finding client users by email domain...');
    
    const customerDomain = customer.email.split('@')[1];
    console.log(`   Customer email: ${customer.email}`);
    console.log(`   Customer domain: @${customerDomain}`);
    console.log(`   Customer organization: ${customerOrg}`);
    
    const clientUIDs = [];
    
    // Check MongoDB for client users with matching domain
    const clientUsersFromDB = await db.collection('users').find({
      role: 'client'
    }).toArray();
    
    clientUsersFromDB.forEach(user => {
      if (user.firebaseUid && user.email) {
        const clientDomain = user.email.split('@')[1];
        // Match by email domain (case-insensitive)
        if (clientDomain.toLowerCase() === customerDomain.toLowerCase()) {
          clientUIDs.push({
            uid: user.firebaseUid,
            email: user.email,
            domain: clientDomain,
            org: user.companyName || user.organizationName
          });
        }
      }
    });
    
    console.log(`   Found ${clientUIDs.length} client(s) in MongoDB with domain @${customerDomain}`);
    
    // Check Firestore for client users with matching domain
    try {
      const firestore = admin.firestore();
      const usersSnapshot = await firestore.collection('users')
        .where('role', '==', 'client')
        .get();
      
      usersSnapshot.forEach(doc => {
        const uid = doc.id;
        const userData = doc.data();
        
        if (userData.email) {
          const clientDomain = userData.email.split('@')[1];
          // Match by email domain (case-insensitive)
          if (clientDomain.toLowerCase() === customerDomain.toLowerCase()) {
            // Check if not already added
            if (!clientUIDs.find(c => c.uid === uid)) {
              clientUIDs.push({
                uid: uid,
                email: userData.email,
                domain: clientDomain,
                org: userData.companyName || userData.organizationName
              });
              console.log(`   Found additional client in Firestore: ${userData.email}`);
            }
          }
        }
      });
    } catch (firestoreError) {
      console.warn('⚠️  Could not check Firestore:', firestoreError.message);
    }
    
    console.log(`\n✅ Total unique client users with domain @${customerDomain}: ${clientUIDs.length}`);
    clientUIDs.forEach(client => {
      console.log(`   - ${client.email} (${client.uid})`);
      console.log(`     Domain: @${client.domain}`);
      console.log(`     Organization: ${client.org}`);
    });
    
    if (clientUIDs.length === 0) {
      console.log('\n❌ No client users found in organization');
      console.log('   This is why the customer is not receiving notifications!');
      return;
    }
    
    // Step 3: Check existing notifications for these clients
    console.log('\n📋 Step 3: Checking existing notifications...');
    for (const client of clientUIDs) {
      const notificationsRef = admin.database().ref(`notifications/${client.uid}`);
      const snapshot = await notificationsRef.once('value');
      const notifications = snapshot.val();
      
      if (notifications) {
        const notifArray = Object.values(notifications);
        const leaveNotifs = notifArray.filter(n => n.type === 'leave_request');
        console.log(`   ${client.email}: ${notifArray.length} total, ${leaveNotifs.length} leave requests`);
      } else {
        console.log(`   ${client.email}: No notifications`);
      }
    }
    
    // Step 4: Send test notification
    console.log('\n📋 Step 4: Sending test leave request notification...');
    const testNotification = {
      id: `test_${Date.now()}`,
      type: 'leave_request',
      title: 'TEST: New Leave Request - Approval Required',
      body: `${customer.name} has requested leave from Dec 11, 2025 to Dec 12, 2025. 2 trip(s) will be affected. Please review and approve.`,
      data: {
        leaveRequestId: 'test_leave_123',
        customerId: customer.firebaseUid,
        customerName: customer.name,
        customerEmail: customer.email,
        organizationName: customerOrg,
        startDate: '2025-12-11T00:00:00.000Z',
        endDate: '2025-12-12T00:00:00.000Z',
        reason: 'Medical leave',
        affectedTripsCount: 2
      },
      isRead: false,
      priority: 'high',
      category: 'leave_management',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
    };
    
    for (const client of clientUIDs) {
      const firebasePath = `notifications/${client.uid}/${testNotification.id}`;
      await admin.database().ref(firebasePath).set(testNotification);
      console.log(`✅ Notification sent to: ${client.email}`);
      console.log(`   Path: ${firebasePath}`);
    }
    
    // Step 5: Verify notifications were created
    console.log('\n📋 Step 5: Verifying notifications...');
    for (const client of clientUIDs) {
      const notificationRef = admin.database().ref(`notifications/${client.uid}/${testNotification.id}`);
      const snapshot = await notificationRef.once('value');
      const notification = snapshot.val();
      
      if (notification) {
        console.log(`✅ Verified notification for ${client.email}`);
        console.log(`   Title: ${notification.title}`);
        console.log(`   Type: ${notification.type}`);
        console.log(`   Priority: ${notification.priority}`);
      } else {
        console.log(`❌ Notification not found for ${client.email}`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ TEST COMPLETED');
    console.log('='.repeat(80));
    console.log('\n📝 Next Steps:');
    console.log('1. Check the client dashboard notification bell');
    console.log('2. Verify the notification appears in the list');
    console.log('3. Click on the notification to mark it as read');
    console.log('4. Submit a real leave request from customer dashboard');
    console.log('5. Verify client receives the notification');
    
  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await mongoClient.close();
    process.exit(0);
  }
}

testCustomerLeaveNotification();
