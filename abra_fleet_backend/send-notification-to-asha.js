// send-notification-to-asha.js
// Send a test notification to Asha to verify the system works

const { MongoClient } = require('mongodb');
const path = require('path');

const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

// Initialize Firebase Admin using the same method as the backend
const admin = require('./config/firebase');

async function sendNotificationToAsha() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📤 SENDING TEST NOTIFICATION TO ASHA');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    const ashaUid = 'QpAmlOj1J3UgPpdZ5Rqf0biIGoY2';
    
    // Create notification document
    const notification = {
      userId: ashaUid,
      type: 'route_assigned',
      title: '🚗 Your Ride is Confirmed!',
      body: 'Your roster has been assigned.\n\nDriver: Vikyath M\nVehicle: KA01AB1234\n\nYou will be picked up according to the schedule.',
      data: {
        driverName: 'Vikyath M',
        vehicleName: 'KA01AB1234',
        pickupSequence: 1,
        totalStops: 1,
        action: 'route_assignment'
      },
      metadata: {
        rosterId: '693a57a81f77993e2eb68929',
        driverId: 'EMP001',
        vehicleId: '68e9e9e20cc297dd3ab4bd97',
        action: 'route_assigned'
      },
      isRead: false,
      readAt: null,
      priority: 'high',
      category: 'roster',
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days
      deliveryStatus: {
        mongodb: 'pending',
        firebaseRTDB: 'pending',
        fcmMobile: 'pending',
        fcmWeb: 'pending'
      }
    };
    
    // Step 1: Save to MongoDB
    console.log('\n📋 Step 1: Saving to MongoDB...');
    const result = await db.collection('notifications').insertOne(notification);
    console.log(`   ✅ Saved to MongoDB: ${result.insertedId}`);
    
    // Update delivery status
    await db.collection('notifications').updateOne(
      { _id: result.insertedId },
      { $set: { 'deliveryStatus.mongodb': 'success' } }
    );
    
    // Step 2: Push to Firebase RTDB
    console.log('\n📋 Step 2: Pushing to Firebase RTDB...');
    try {
      const firebaseNotification = {
        id: result.insertedId.toString(),
        userId: ashaUid,
        type: notification.type,
        title: notification.title,
        body: notification.body,
        data: notification.data,
        metadata: notification.metadata,
        isRead: false,
        priority: notification.priority,
        category: notification.category,
        createdAt: notification.createdAt.toISOString(),
        expiresAt: notification.expiresAt.toISOString()
      };
      
      const firebasePath = `notifications/${ashaUid}/${result.insertedId.toString()}`;
      console.log(`   Path: ${firebasePath}`);
      
      await admin.database().ref(firebasePath).set(firebaseNotification);
      console.log('   ✅ Pushed to Firebase RTDB successfully!');
      
      // Update delivery status
      await db.collection('notifications').updateOne(
        { _id: result.insertedId },
        { $set: { 'deliveryStatus.firebaseRTDB': 'success' } }
      );
    } catch (fbError) {
      console.log(`   ❌ Firebase RTDB failed: ${fbError.message}`);
      await db.collection('notifications').updateOne(
        { _id: result.insertedId },
        { $set: { 'deliveryStatus.firebaseRTDB': 'failed' } }
      );
    }
    
    // Step 3: Verify
    console.log('\n📋 Step 3: Verifying...');
    const savedNotification = await db.collection('notifications').findOne({ _id: result.insertedId });
    console.log(`   MongoDB Status: ${savedNotification.deliveryStatus.mongodb}`);
    console.log(`   Firebase RTDB Status: ${savedNotification.deliveryStatus.firebaseRTDB}`);
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ NOTIFICATION SENT!');
    console.log('='.repeat(80));
    console.log('\nAsha should now see the notification in her app.');
    console.log('If Firebase RTDB succeeded, it will appear in real-time.');
    console.log('If not, she needs to refresh the notifications screen.');
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

sendNotificationToAsha();
