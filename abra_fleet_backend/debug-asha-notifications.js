// debug-asha-notifications.js
// Debug why asha123@cognizant.com is not receiving notifications

const { MongoClient } = require('mongodb');

const MONGO_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function debugAshaNotifications() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 DEBUGGING NOTIFICATIONS FOR: asha123@cognizant.com');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    // 1. Find the user
    console.log('\n📋 Step 1: Finding user in database...');
    const user = await db.collection('users').findOne({
      email: { $regex: /asha123@cognizant.com/i }
    });
    
    if (user) {
      console.log('✅ User FOUND:');
      console.log(`   - Name: ${user.name}`);
      console.log(`   - Email: ${user.email}`);
      console.log(`   - Firebase UID: ${user.firebaseUid}`);
      console.log(`   - Role: ${user.role}`);
      console.log(`   - Organization: ${user.companyName || user.organizationName}`);
      console.log(`   - Status: ${user.status}`);
    } else {
      console.log('❌ User NOT FOUND in users collection!');
      console.log('   This is likely the problem - user needs to be registered.');
      return;
    }
    
    // 2. Find rosters for this user
    console.log('\n📋 Step 2: Finding rosters for this user...');
    const rosters = await db.collection('rosters').find({
      $or: [
        { customerEmail: { $regex: /asha123@cognizant.com/i } },
        { 'employeeDetails.email': { $regex: /asha123@cognizant.com/i } },
        { customerId: user.firebaseUid }
      ]
    }).toArray();
    
    console.log(`   Found ${rosters.length} rosters`);
    
    if (rosters.length > 0) {
      for (const roster of rosters) {
        console.log(`\n   Roster ID: ${roster._id}`);
        console.log(`   - Status: ${roster.status}`);
        console.log(`   - Customer Email: ${roster.customerEmail}`);
        console.log(`   - Customer ID: ${roster.customerId}`);
        console.log(`   - Assigned Driver: ${roster.assignedDriver?.driverName || 'Not assigned'}`);
        console.log(`   - Assigned Vehicle: ${roster.assignedVehicle?.vehicleNumber || 'Not assigned'}`);
        console.log(`   - Created: ${roster.createdAt}`);
        console.log(`   - Updated: ${roster.updatedAt}`);
      }
    } else {
      console.log('   ❌ No rosters found for this user!');
    }
    
    // 3. Check notifications for this user
    console.log('\n📋 Step 3: Checking notifications...');
    
    // Try multiple ways to find notifications
    const notificationQueries = [
      { userId: user.firebaseUid },
      { userId: user.email },
      { userId: { $regex: /asha123@cognizant.com/i } },
      { 'data.customerEmail': { $regex: /asha123@cognizant.com/i } }
    ];
    
    let allNotifications = [];
    for (const query of notificationQueries) {
      const notifications = await db.collection('notifications').find(query).toArray();
      if (notifications.length > 0) {
        console.log(`   Query ${JSON.stringify(query)} found ${notifications.length} notifications`);
        allNotifications = allNotifications.concat(notifications);
      }
    }
    
    // Remove duplicates
    const uniqueNotifications = [...new Map(allNotifications.map(n => [n._id.toString(), n])).values()];
    
    console.log(`\n   Total unique notifications: ${uniqueNotifications.length}`);
    
    if (uniqueNotifications.length > 0) {
      console.log('\n   📱 Notifications found:');
      uniqueNotifications.forEach(notif => {
        console.log(`\n   - ID: ${notif._id}`);
        console.log(`     Title: ${notif.title}`);
        console.log(`     Type: ${notif.type}`);
        console.log(`     UserId: ${notif.userId}`);
        console.log(`     Read: ${notif.read}`);
        console.log(`     Created: ${notif.createdAt}`);
      });
    } else {
      console.log('   ❌ NO NOTIFICATIONS FOUND for this user!');
    }
    
    // 4. Check if assigned rosters have notifications
    console.log('\n📋 Step 4: Checking if assigned rosters triggered notifications...');
    
    const assignedRosters = rosters.filter(r => r.status === 'assigned');
    console.log(`   Found ${assignedRosters.length} assigned rosters`);
    
    for (const roster of assignedRosters) {
      const rosterNotifications = await db.collection('notifications').find({
        'data.rosterId': roster._id.toString()
      }).toArray();
      
      console.log(`\n   Roster ${roster._id}:`);
      console.log(`   - Notifications for this roster: ${rosterNotifications.length}`);
      
      if (rosterNotifications.length === 0) {
        console.log('   ⚠️  NO NOTIFICATION was created when this roster was assigned!');
        console.log('   PROBLEM: The notification was not sent during assignment.');
      }
    }
    
    // 5. Diagnose the problem
    console.log('\n' + '='.repeat(80));
    console.log('🔍 DIAGNOSIS');
    console.log('='.repeat(80));
    
    if (!user) {
      console.log('\n❌ PROBLEM: User does not exist in database');
      console.log('   SOLUTION: User needs to register or be created via roster import');
    } else if (!user.firebaseUid) {
      console.log('\n❌ PROBLEM: User has no Firebase UID');
      console.log('   SOLUTION: User needs to complete registration');
    } else if (rosters.length === 0) {
      console.log('\n❌ PROBLEM: No rosters found for this user');
      console.log('   SOLUTION: Create rosters for this user');
    } else if (assignedRosters.length === 0) {
      console.log('\n❌ PROBLEM: No rosters are assigned yet');
      console.log('   SOLUTION: Admin needs to assign rosters via route optimization');
    } else if (uniqueNotifications.length === 0) {
      console.log('\n❌ PROBLEM: Notifications were NOT created during assignment');
      console.log('   POSSIBLE CAUSES:');
      console.log('   1. The userId used for notification does not match user.firebaseUid');
      console.log('   2. The createNotification function failed silently');
      console.log('   3. The roster was assigned before notification code was added');
      console.log('\n   SOLUTION: Check the userId being used in createNotification');
      
      // Check what userId is stored in roster
      if (assignedRosters.length > 0) {
        const roster = assignedRosters[0];
        console.log('\n   📋 Roster userId fields:');
        console.log(`   - roster.customerId: ${roster.customerId}`);
        console.log(`   - roster.customerEmail: ${roster.customerEmail}`);
        console.log(`   - user.firebaseUid: ${user.firebaseUid}`);
        
        if (roster.customerId !== user.firebaseUid) {
          console.log('\n   ⚠️  MISMATCH DETECTED!');
          console.log('   The roster.customerId does not match user.firebaseUid');
          console.log('   This is why notifications are not being found!');
        }
      }
    }
    
    // 6. Provide fix
    console.log('\n' + '='.repeat(80));
    console.log('🔧 RECOMMENDED FIX');
    console.log('='.repeat(80));
    
    if (user && assignedRosters.length > 0 && uniqueNotifications.length === 0) {
      console.log('\nTo fix this, we need to:');
      console.log('1. Update rosters to use correct customerId (Firebase UID)');
      console.log('2. Send a test notification to verify the system works');
      console.log('\nRun: node abra_fleet_backend/fix-asha-notifications.js');
    }
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

debugAshaNotifications();
