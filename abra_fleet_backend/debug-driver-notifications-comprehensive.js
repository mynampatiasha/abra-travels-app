// Comprehensive Driver Notifications Debug Script
const axios = require('axios');
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./config/firebase-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com/'
});

const API_BASE_URL = 'http://localhost:3001/api';

async function debugDriverNotifications() {
  console.log('🔍 COMPREHENSIVE DRIVER NOTIFICATIONS DEBUG');
  console.log('==========================================\n');

  try {
    // Step 1: Check if driver exists and get Firebase UID
    console.log('1️⃣ CHECKING DRIVER AUTHENTICATION...');
    
    const driverEmail = 'drivertest@gmail.com';
    let driverFirebaseUID = null;
    
    try {
      const userRecord = await admin.auth().getUserByEmail(driverEmail);
      driverFirebaseUID = userRecord.uid;
      console.log(`✅ Driver Firebase UID: ${driverFirebaseUID}`);
    } catch (error) {
      console.log(`❌ Driver not found in Firebase Auth: ${error.message}`);
      return;
    }

    // Step 2: Create custom token for testing
    console.log('\n2️⃣ CREATING CUSTOM TOKEN...');
    const customToken = await admin.auth().createCustomToken(driverFirebaseUID);
    console.log('✅ Custom token created');

    // Step 3: Test notifications API with authentication
    console.log('\n3️⃣ TESTING NOTIFICATIONS API...');
    
    try {
      const response = await axios.get(`${API_BASE_URL}/notifications`, {
        headers: {
          'Authorization': `Bearer ${customToken}`,
          'Content-Type': 'application/json'
        },
        timeout: 10000
      });

      console.log(`✅ API Response Status: ${response.status}`);
      console.log(`📬 Notifications found: ${response.data.data?.notifications?.length || 0}`);
      
      if (response.data.data?.notifications?.length > 0) {
        console.log('\n📋 NOTIFICATION DETAILS:');
        response.data.data.notifications.forEach((notification, index) => {
          console.log(`   ${index + 1}. ${notification.title}`);
          console.log(`      Type: ${notification.type}`);
          console.log(`      Read: ${notification.isRead}`);
          console.log(`      Date: ${notification.createdAt}`);
        });
      } else {
        console.log('⚠️  No notifications found for this driver');
      }

    } catch (apiError) {
      console.log(`❌ API Error: ${apiError.message}`);
      if (apiError.response) {
        console.log(`   Status: ${apiError.response.status}`);
        console.log(`   Response: ${JSON.stringify(apiError.response.data, null, 2)}`);
      }
    }

    // Step 4: Check MongoDB directly
    console.log('\n4️⃣ CHECKING MONGODB DIRECTLY...');
    
    try {
      const { MongoClient } = require('mongodb');
      const client = new MongoClient('mongodb://localhost:27017');
      await client.connect();
      
      const db = client.db('abra_fleet');
      const notifications = await db.collection('notifications')
        .find({ userId: driverFirebaseUID })
        .sort({ createdAt: -1 })
        .limit(10)
        .toArray();
      
      console.log(`📊 MongoDB notifications count: ${notifications.length}`);
      
      if (notifications.length > 0) {
        console.log('\n📋 MONGODB NOTIFICATION DETAILS:');
        notifications.forEach((notification, index) => {
          console.log(`   ${index + 1}. ${notification.title}`);
          console.log(`      Type: ${notification.type}`);
          console.log(`      Read: ${notification.isRead}`);
          console.log(`      User ID: ${notification.userId}`);
        });
      }
      
      await client.close();
      
    } catch (mongoError) {
      console.log(`❌ MongoDB Error: ${mongoError.message}`);
    }

    // Step 5: Check Firebase Realtime Database
    console.log('\n5️⃣ CHECKING FIREBASE REALTIME DATABASE...');
    
    try {
      const rtdbRef = admin.database().ref(`notifications/${driverFirebaseUID}`);
      const snapshot = await rtdbRef.once('value');
      const rtdbNotifications = snapshot.val();
      
      if (rtdbNotifications) {
        const notificationCount = Object.keys(rtdbNotifications).length;
        console.log(`📊 Firebase RTDB notifications count: ${notificationCount}`);
        
        console.log('\n📋 RTDB NOTIFICATION DETAILS:');
        Object.entries(rtdbNotifications).forEach(([key, notification], index) => {
          console.log(`   ${index + 1}. ${notification.title}`);
          console.log(`      Type: ${notification.type}`);
          console.log(`      Key: ${key}`);
        });
      } else {
        console.log('⚠️  No notifications found in Firebase RTDB');
      }
      
    } catch (rtdbError) {
      console.log(`❌ Firebase RTDB Error: ${rtdbError.message}`);
    }

    // Step 6: Test FCM token
    console.log('\n6️⃣ CHECKING FCM TOKEN...');
    
    try {
      const fcmTokenRef = admin.database().ref(`fcm_tokens/${driverFirebaseUID}`);
      const fcmSnapshot = await fcmTokenRef.once('value');
      const fcmData = fcmSnapshot.val();
      
      if (fcmData && fcmData.token) {
        console.log('✅ FCM token found');
        console.log(`   Platform: ${fcmData.platform || 'unknown'}`);
        console.log(`   Last updated: ${fcmData.lastUpdated || 'unknown'}`);
      } else {
        console.log('⚠️  No FCM token found');
      }
      
    } catch (fcmError) {
      console.log(`❌ FCM Token Error: ${fcmError.message}`);
    }

  } catch (error) {
    console.log(`❌ General Error: ${error.message}`);
  }

  console.log('\n🏁 DEBUG COMPLETE');
}

// Run the debug
debugDriverNotifications().catch(console.error);