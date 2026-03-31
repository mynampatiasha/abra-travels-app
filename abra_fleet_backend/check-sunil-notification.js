// Check Sunil's notification to see what data was sent
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function checkSunilNotification() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find Sunil's user
    const sunilUser = await db.collection('users').findOne({
      email: 'sunil.gupta@wipro.com'
    });
    
    if (!sunilUser) {
      console.log('❌ Sunil user not found');
      return;
    }
    
    console.log('✅ Found Sunil');
    console.log('  Firebase UID:', sunilUser.firebaseUid);
    console.log('  Email:', sunilUser.email);
    
    // Find his notifications
    console.log('\n📬 Checking Sunil\'s notifications...\n');
    
    const notifications = await db.collection('notifications')
      .find({ 
        userId: sunilUser.firebaseUid
      })
      .sort({ createdAt: -1 })
      .limit(3)
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
      
      console.log('\n📊 Data Fields:');
      console.log(JSON.stringify(notif.data, null, 2));
      
      console.log('\n🔍 Field Check:');
      console.log('  driverPhone:', notif.data?.driverPhone || '❌ MISSING');
      console.log('  loginTime:', notif.data?.loginTime || '❌ MISSING');
      console.log('  logoutTime:', notif.data?.logoutTime || '❌ MISSING');
      console.log('  loginLocation:', notif.data?.loginLocation || '❌ MISSING');
      console.log('  logoutLocation:', notif.data?.logoutLocation || '❌ MISSING');
      console.log('  startTime:', notif.data?.startTime || '❌ MISSING');
      console.log('  endTime:', notif.data?.endTime || '❌ MISSING');
    });
    
    // Check his roster
    console.log('\n\n📋 Checking Sunil\'s roster...\n');
    
    const roster = await db.collection('rosters').findOne({
      _id: new ObjectId('693ba0a3ac2f88dc06b55385')
    });
    
    if (roster) {
      console.log('✅ Found roster');
      console.log('\n📊 Roster Schedule Data:');
      console.log('  startTime:', roster.startTime);
      console.log('  endTime:', roster.endTime);
      console.log('  loginTime:', roster.loginTime || 'N/A');
      console.log('  logoutTime:', roster.logoutTime || 'N/A');
      
      console.log('\n📍 Roster Location Data:');
      console.log('  pickupLocation:', typeof roster.pickupLocation === 'object' ? roster.pickupLocation.address : roster.pickupLocation);
      console.log('  loginLocation:', roster.loginLocation || 'N/A');
      console.log('  locations.drop.address:', roster.locations?.drop?.address || 'N/A');
      console.log('  logoutLocation:', roster.logoutLocation || 'N/A');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ Check complete');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkSunilNotification();
