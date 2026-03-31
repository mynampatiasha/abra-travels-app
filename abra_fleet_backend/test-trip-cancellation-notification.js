// Test script to verify trip cancellation notification flow
require('dotenv').config();
const admin = require('firebase-admin');
const { MongoClient, ObjectId } = require('mongodb');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
    databaseURL: process.env.FIREBASE_DATABASE_URL,
  });
}

const db = admin.database();

async function testTripCancellationNotification() {
  console.log('🧪 ========================================');
  console.log('🧪 TESTING TRIP CANCELLATION NOTIFICATION');
  console.log('🧪 ========================================\n');

  let mongoClient;

  try {
    // Connect to MongoDB
    mongoClient = await MongoClient.connect(process.env.MONGODB_URI);
    const database = mongoClient.db(process.env.MONGODB_DB_NAME || 'abra_fleet');
    
    console.log('✅ Connected to MongoDB\n');

    // Step 1: Find an admin user
    console.log('📋 Step 1: Finding admin user...');
    const adminUser = await database.collection('users').findOne({ role: 'admin' });
    
    if (!adminUser) {
      console.log('❌ No admin user found');
      return;
    }
    
    console.log(`✅ Found admin: ${adminUser.name} (${adminUser.email})`);
    console.log(`   Firebase UID: ${adminUser.firebaseUid}\n`);

    // Step 2: Create test notification data
    console.log('📋 Step 2: Creating test notification...');
    
    const notificationData = {
      userId: adminUser.firebaseUid,
      type: 'trip_cancelled',
      title: '✅ Trips Cancelled Successfully',
      body: 'Successfully cancelled 3 trip(s) for Test Customer',
      priority: 'high',
      category: 'trip_management',
      isRead: false,
      createdAt: new Date(),
      data: {
        leaveRequestId: 'test-leave-123',
        customerName: 'Test Customer',
        cancelledTripsCount: 3,
        cancelledTrips: [
          {
            id: 'trip-1',
            readableId: 'TRIP-001',
            rosterType: 'login',
            officeLocation: 'Main Office'
          },
          {
            id: 'trip-2',
            readableId: 'TRIP-002',
            rosterType: 'logout',
            officeLocation: 'Main Office'
          },
          {
            id: 'trip-3',
            readableId: 'TRIP-003',
            rosterType: 'login',
            officeLocation: 'Branch Office'
          }
        ],
        processedBy: adminUser.name,
        processedAt: new Date().toISOString()
      }
    };

    // Step 3: Save to MongoDB
    console.log('💾 Step 3: Saving to MongoDB...');
    const result = await database.collection('notifications').insertOne(notificationData);
    console.log(`✅ Notification saved with ID: ${result.insertedId}\n`);

    // Step 4: Send to Firebase Realtime Database
    console.log('🔥 Step 4: Sending to Firebase RTDB...');
    const notificationRef = db.ref(`notifications/${adminUser.firebaseUid}`).push();
    
    await notificationRef.set({
      id: result.insertedId.toString(),
      type: notificationData.type,
      title: notificationData.title,
      body: notificationData.body,
      priority: notificationData.priority,
      category: notificationData.category,
      isRead: false,
      createdAt: notificationData.createdAt.toISOString(),
      data: notificationData.data,
      metadata: notificationData.data
    });
    
    console.log(`✅ Notification sent to Firebase RTDB`);
    console.log(`   Path: notifications/${adminUser.firebaseUid}/${notificationRef.key}\n`);

    // Step 5: Verify notification
    console.log('🔍 Step 5: Verifying notification...');
    const snapshot = await notificationRef.once('value');
    const savedNotification = snapshot.val();
    
    console.log('✅ Notification verified in Firebase RTDB:');
    console.log(`   Title: ${savedNotification.title}`);
    console.log(`   Body: ${savedNotification.body}`);
    console.log(`   Type: ${savedNotification.type}`);
    console.log(`   Priority: ${savedNotification.priority}`);
    console.log(`   Cancelled Trips: ${savedNotification.data.cancelledTripsCount}\n`);

    console.log('🎉 ========================================');
    console.log('🎉 TEST COMPLETED SUCCESSFULLY!');
    console.log('🎉 ========================================\n');
    console.log('📱 The admin should now receive:');
    console.log('   1. A floating notification with sound');
    console.log('   2. The notification in the notifications screen');
    console.log('   3. Updated badge count on the notification bell\n');

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('✅ MongoDB connection closed');
    }
  }
}

// Run the test
testTripCancellationNotification();
