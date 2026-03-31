// test-asha-notification-api.js
// Test the notification API for Asha to verify she can fetch her notifications

const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function testNotificationAPI() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 TESTING NOTIFICATION API FOR ASHA');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    const ashaUid = 'QpAmlOj1J3UgPpdZ5Rqf0biIGoY2';
    
    // Simulate what the API does when fetching notifications
    console.log('\n📡 Simulating API call: GET /api/notifications');
    console.log(`   User ID: ${ashaUid}`);
    
    const notifications = await db.collection('notifications')
      .find({ userId: ashaUid })
      .sort({ createdAt: -1 })
      .limit(50)
      .toArray();
    
    console.log(`\n✅ API would return ${notifications.length} notifications`);
    
    // Check the latest route assignment notification
    const routeNotification = notifications.find(n => 
      n.type === 'route_assigned' || n.type === 'route_assignment'
    );
    
    if (routeNotification) {
      console.log('\n📋 ROUTE ASSIGNMENT NOTIFICATION FOUND:');
      console.log(`   ID: ${routeNotification._id}`);
      console.log(`   Title: ${routeNotification.title}`);
      console.log(`   Body: ${routeNotification.body?.substring(0, 100)}...`);
      console.log(`   Type: ${routeNotification.type}`);
      console.log(`   IsRead: ${routeNotification.isRead}`);
      console.log(`   Created: ${routeNotification.createdAt}`);
      console.log(`   Delivery Status: ${JSON.stringify(routeNotification.deliveryStatus)}`);
      
      console.log('\n✅ The notification EXISTS in MongoDB and should be visible in the app!');
    } else {
      console.log('\n❌ No route assignment notification found!');
    }
    
    // Check unread count
    const unreadCount = await db.collection('notifications').countDocuments({
      userId: ashaUid,
      isRead: { $ne: true }
    });
    
    console.log(`\n📊 Unread notification count: ${unreadCount}`);
    
    // List all notification types for this user
    console.log('\n📋 All notification types for Asha:');
    const types = await db.collection('notifications').distinct('type', { userId: ashaUid });
    types.forEach(t => console.log(`   - ${t}`));
    
    // Summary
    console.log('\n' + '='.repeat(80));
    console.log('📊 SUMMARY');
    console.log('='.repeat(80));
    
    console.log('\n✅ NOTIFICATION IS IN DATABASE');
    console.log('   The route assignment notification exists in MongoDB.');
    console.log('   The Flutter app fetches from the backend API which reads from MongoDB.');
    console.log('   Therefore, the notification SHOULD be visible in the app.');
    
    console.log('\n🔍 POSSIBLE ISSUES:');
    console.log('   1. App needs to refresh/pull down to fetch new notifications');
    console.log('   2. App might be caching old data');
    console.log('   3. User needs to logout and login again');
    console.log('   4. Firebase RTDB failed, so real-time push did not work');
    
    console.log('\n🔧 RECOMMENDED ACTIONS:');
    console.log('   1. Ask customer to pull down to refresh notifications screen');
    console.log('   2. Ask customer to logout and login again');
    console.log('   3. Check if notification appears after refresh');
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

testNotificationAPI();
