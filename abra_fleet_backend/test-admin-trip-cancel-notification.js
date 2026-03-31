// Test script to send trip cancellation notification to admin
require('dotenv').config();
const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');

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

async function testAdminTripCancelNotification() {
  console.log('🧪 ========================================');
  console.log('🧪 TESTING ADMIN TRIP CANCELLATION NOTIFICATION');
  console.log('🧪 ========================================\n');

  let mongoClient;

  try {
    // Connect to MongoDB
    mongoClient = await MongoClient.connect(process.env.MONGODB_URI);
    const database = mongoClient.db(process.env.MONGODB_DB_NAME || 'abra_fleet');
    
    console.log('✅ Connected to MongoDB\n');

    // Find admin user
    console.log('📋 Step 1: Finding admin user...');
    const adminUser = await database.collection('users').findOne({ 
      role: 'admin',
      firebaseUid: { $exists: true }
    });
    
    if (!adminUser) {
      console.log('❌ No admin user found with Firebase UID');
      return;
    }
    
    console.log(`✅ Found admin: ${adminUser.name} (${adminUser.email})`);
    console.log(`   Firebase UID: ${adminUser.firebaseUid}\n`);

    // Create notification
    console.log('📋 Step 2: Creating trip cancellation notification...');
    
    const notificationData = {
      userId: adminUser.firebaseUid,
      type: 'trip_cancelled',
      title: '✅ Trips Cancelled Successfully',
      body: 'Successfully cancelled 3 trip(s) for John Doe',
      priority: 'high',
      category: 'trip_management',
      isRead: false,
      createdAt: new Date(),
      data: {
        leaveRequestId: 'test-leave-123',
        customerName: 'John Doe',
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

    // Save to MongoDB
    console.log('💾 Step 3: Saving to MongoDB...');
    const result = await database.collection('notifications').insertOne(notificationData);
    console.log(`✅ Saved to MongoDB with ID: ${result.insertedId}\n`);

    // Send to Firebase RTDB
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
    
    console.log(`✅ Sent to Firebase RTDB`);
    console.log(`   Path: notifications/${adminUser.firebaseUid}/${notificationRef.key}\n`);

    console.log('🎉 ========================================');
    console.log('🎉 TEST COMPLETED SUCCESSFULLY!');
    console.log('🎉 ========================================\n');
    console.log('📱 Admin should now see:');
    console.log('   1. 🔊 Notification sound plays');
    console.log('   2. 📬 Floating notification appears');
    console.log('   3. 🔔 Badge count increases');
    console.log('   4. 📋 Notification in list\n');
    console.log(`👤 Admin: ${adminUser.name}`);
    console.log(`📧 Email: ${adminUser.email}`);
    console.log(`🆔 Firebase UID: ${adminUser.firebaseUid}\n`);

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
testAdminTripCancelNotification();
