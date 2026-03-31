// check-asha-notification-details.js
// Check the full notification details for Asha

const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function checkNotificationDetails() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 CHECKING ASHA\'S NOTIFICATION DETAILS');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    const ashaUid = 'QpAmlOj1J3UgPpdZ5Rqf0biIGoY2';
    
    // Get all notifications for Asha
    const notifications = await db.collection('notifications').find({
      userId: ashaUid
    }).sort({ createdAt: -1 }).toArray();
    
    console.log(`\n📱 Found ${notifications.length} notifications for Asha:`);
    
    notifications.forEach((n, i) => {
      console.log(`\n${'='.repeat(60)}`);
      console.log(`Notification ${i + 1}:`);
      console.log(JSON.stringify(n, null, 2));
    });
    
    // Check the latest route_assigned notification
    const routeNotification = await db.collection('notifications').findOne({
      _id: new ObjectId('693ab6243530aee5fcbea8fd')
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('📋 LATEST ROUTE ASSIGNMENT NOTIFICATION (Full Details):');
    console.log('='.repeat(80));
    console.log(JSON.stringify(routeNotification, null, 2));
    
    // Check if notification is properly formatted for the app
    console.log('\n' + '='.repeat(80));
    console.log('🔍 NOTIFICATION FORMAT CHECK');
    console.log('='.repeat(80));
    
    if (routeNotification) {
      console.log('\nRequired fields for app display:');
      console.log(`✅ _id: ${routeNotification._id ? 'Present' : 'MISSING'}`);
      console.log(`✅ userId: ${routeNotification.userId ? 'Present' : 'MISSING'}`);
      console.log(`✅ title: ${routeNotification.title ? 'Present' : 'MISSING'}`);
      console.log(`✅ message: ${routeNotification.message ? 'Present' : 'MISSING'}`);
      console.log(`✅ type: ${routeNotification.type ? 'Present' : 'MISSING'}`);
      console.log(`✅ createdAt: ${routeNotification.createdAt ? 'Present' : 'MISSING'}`);
      console.log(`✅ read: ${routeNotification.read !== undefined ? 'Present' : 'MISSING (defaults to false)'}`);
    }
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

checkNotificationDetails();
