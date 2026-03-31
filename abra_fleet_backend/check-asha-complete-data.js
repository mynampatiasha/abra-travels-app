// Check Asha's complete data - roster and notifications
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function checkAshaCompleteData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find Asha's user
    const ashaUser = await db.collection('users').findOne({
      email: 'asha123@cognizant.com'
    });
    
    if (!ashaUser) {
      console.log('❌ Asha user not found');
      return;
    }
    
    console.log('✅ Found Asha');
    console.log('  Firebase UID:', ashaUser.firebaseUid);
    console.log('  Email:', ashaUser.email);
    
    // Find her rosters
    console.log('\n📋 Checking Asha\'s rosters...\n');
    
    const rosters = await db.collection('rosters')
      .find({ 
        $or: [
          { customerEmail: 'asha123@cognizant.com' },
          { userId: ashaUser.firebaseUid }
        ]
      })
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    console.log(`Found ${rosters.length} rosters\n`);
    
    rosters.forEach((roster, index) => {
      console.log(`\nRoster ${index + 1}: ${roster._id.toString()}`);
      console.log('  Status:', roster.status);
      console.log('  startTime:', roster.startTime || 'N/A');
      console.log('  endTime:', roster.endTime || 'N/A');
      console.log('  loginTime:', roster.loginTime || 'N/A');
      console.log('  logoutTime:', roster.logoutTime || 'N/A');
      console.log('  pickupLocation:', roster.pickupLocation || 'N/A');
      console.log('  loginLocation:', roster.loginLocation || 'N/A');
      console.log('  dropLocation:', roster.dropLocation || 'N/A');
      console.log('  logoutLocation:', roster.logoutLocation || 'N/A');
    });
    
    // Find her notifications
    console.log('\n\n📬 Checking Asha\'s notifications...\n');
    
    const notifications = await db.collection('notifications')
      .find({ 
        userId: ashaUser.firebaseUid
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
      
      console.log('\n📊 ALL Data Fields:');
      if (notif.data && Object.keys(notif.data).length > 0) {
        Object.keys(notif.data).forEach(key => {
          console.log(`  ${key}:`, notif.data[key]);
        });
      } else {
        console.log('  ❌ No data fields');
      }
      
      console.log('\n🔍 Missing Fields Check:');
      const missingFields = [];
      if (!notif.data?.driverPhone) missingFields.push('driverPhone');
      if (!notif.data?.loginTime && !notif.data?.startTime) missingFields.push('loginTime/startTime');
      if (!notif.data?.logoutTime && !notif.data?.endTime) missingFields.push('logoutTime/endTime');
      if (!notif.data?.loginLocation && !notif.data?.pickupLocation) missingFields.push('loginLocation/pickupLocation');
      if (!notif.data?.logoutLocation && !notif.data?.dropLocation) missingFields.push('logoutLocation/dropLocation');
      
      if (missingFields.length > 0) {
        console.log('  ❌ Missing:', missingFields.join(', '));
      } else {
        console.log('  ✅ All fields present');
      }
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('📝 SUMMARY');
    console.log('='.repeat(80));
    console.log('Total Rosters:', rosters.length);
    console.log('Total Notifications:', notifications.length);
    console.log('\n💡 To see new fields:');
    console.log('1. Restart backend');
    console.log('2. Assign a roster to Asha from admin panel');
    console.log('3. Check the NEW notification');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAshaCompleteData();
