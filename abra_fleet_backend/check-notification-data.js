// Check notification data structure
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function checkNotificationData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Find recent roster_assigned notifications
    console.log('\n📋 Checking recent roster_assigned notifications...\n');
    
    const notifications = await db.collection('notifications')
      .find({ 
        type: { $in: ['roster_assigned', 'route_assigned', 'route_assignment'] }
      })
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    console.log(`Found ${notifications.length} notifications\n`);
    
    notifications.forEach((notif, index) => {
      console.log(`\n${'='.repeat(80)}`);
      console.log(`Notification ${index + 1}:`);
      console.log(`${'='.repeat(80)}`);
      console.log('ID:', notif._id.toString());
      console.log('Type:', notif.type);
      console.log('Title:', notif.title);
      console.log('Created:', notif.createdAt);
      console.log('\nData fields:');
      console.log(JSON.stringify(notif.data, null, 2));
      
      // Check for specific fields
      console.log('\n🔍 Field Check:');
      console.log('  driverPhone:', notif.data?.driverPhone || '❌ MISSING');
      console.log('  loginTime:', notif.data?.loginTime || '❌ MISSING');
      console.log('  logoutTime:', notif.data?.logoutTime || '❌ MISSING');
      console.log('  loginLocation:', notif.data?.loginLocation || '❌ MISSING');
      console.log('  logoutLocation:', notif.data?.logoutLocation || '❌ MISSING');
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ Check complete');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkNotificationData();
