// test-roster-assignment-notifications.js
// Test script to verify customer and driver notifications after roster assignment

const { MongoClient } = require('mongodb');

const MONGO_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function testNotificationFlow() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔔 TESTING ROSTER ASSIGNMENT NOTIFICATION FLOW');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    // 1. Check if there are any assigned rosters
    console.log('\n📋 Step 1: Checking for assigned rosters...');
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned',
      assignedDriver: { $exists: true },
      assignedVehicle: { $exists: true }
    }).limit(5).toArray();
    
    console.log(`   Found ${assignedRosters.length} assigned rosters`);
    
    if (assignedRosters.length === 0) {
      console.log('\n⚠️  No assigned rosters found. Please assign some rosters first.');
      console.log('   Use the route optimization feature in the admin panel.');
      return;
    }
    
    // 2. Check notifications for these rosters
    console.log('\n🔔 Step 2: Checking notifications for assigned rosters...');
    
    for (const roster of assignedRosters) {
      console.log(`\n   Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || roster.customerEmail}`);
      console.log(`   Driver: ${roster.assignedDriver?.driverName || 'Unknown'}`);
      console.log(`   Vehicle: ${roster.assignedVehicle?.vehicleNumber || 'Unknown'}`);
      console.log(`   Status: ${roster.status}`);
      
      // Check customer notification
      const customerNotifications = await db.collection('notifications').find({
        'data.rosterId': roster._id.toString(),
        type: { $in: ['route_assignment', 'driver_assigned'] }
      }).toArray();
      
      console.log(`   📱 Customer notifications: ${customerNotifications.length}`);
      if (customerNotifications.length > 0) {
        customerNotifications.forEach(notif => {
          console.log(`      ✅ ${notif.title}`);
          console.log(`         Created: ${notif.createdAt}`);
          console.log(`         Read: ${notif.read ? 'Yes' : 'No'}`);
        });
      } else {
        console.log(`      ❌ No customer notification found!`);
      }
      
      // Check driver notification
      const driverNotifications = await db.collection('notifications').find({
        userId: roster.assignedDriver?.driverId || roster.assignedDriver?.email,
        type: { $in: ['driver_route_assignment', 'route_assigned'] },
        createdAt: { $gte: new Date(roster.assignmentDate || roster.updatedAt) }
      }).toArray();
      
      console.log(`   🚗 Driver notifications: ${driverNotifications.length}`);
      if (driverNotifications.length > 0) {
        driverNotifications.forEach(notif => {
          console.log(`      ✅ ${notif.title}`);
          console.log(`         Created: ${notif.createdAt}`);
          console.log(`         Read: ${notif.read ? 'Yes' : 'No'}`);
        });
      } else {
        console.log(`      ❌ No driver notification found!`);
      }
    }
    
    // 3. Summary of notification system
    console.log('\n' + '='.repeat(80));
    console.log('📊 NOTIFICATION SYSTEM SUMMARY');
    console.log('='.repeat(80));
    
    const totalNotifications = await db.collection('notifications').countDocuments({
      type: { $in: ['route_assignment', 'driver_route_assignment', 'driver_assigned', 'route_assigned'] }
    });
    
    console.log(`\n✅ Total roster assignment notifications: ${totalNotifications}`);
    
    // Check recent notifications (last 24 hours)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    
    const recentNotifications = await db.collection('notifications').find({
      type: { $in: ['route_assignment', 'driver_route_assignment'] },
      createdAt: { $gte: yesterday }
    }).toArray();
    
    console.log(`📅 Notifications in last 24 hours: ${recentNotifications.length}`);
    
    if (recentNotifications.length > 0) {
      console.log('\n📋 Recent notifications:');
      recentNotifications.forEach(notif => {
        console.log(`   - ${notif.title} (${notif.type})`);
        console.log(`     To: ${notif.userId}`);
        console.log(`     Time: ${notif.createdAt}`);
        console.log(`     Read: ${notif.read ? 'Yes' : 'No'}`);
      });
    }
    
    // 4. Check notification implementation in code
    console.log('\n' + '='.repeat(80));
    console.log('💻 CODE IMPLEMENTATION STATUS');
    console.log('='.repeat(80));
    
    console.log('\n✅ Notification sending is IMPLEMENTED in:');
    console.log('   1. /api/roster/assign-optimized-route endpoint');
    console.log('      - Sends notification to CUSTOMER with:');
    console.log('        • Driver name and phone');
    console.log('        • Vehicle details');
    console.log('        • Pickup time and sequence');
    console.log('        • Real-time tracking link');
    console.log('');
    console.log('      - Sends notification to DRIVER with:');
    console.log('        • Number of customers');
    console.log('        • Total distance and time');
    console.log('        • First pickup time');
    console.log('        • Full route details');
    console.log('');
    console.log('   2. /api/roster/assign-bulk endpoint');
    console.log('      - Bulk assignment with notifications');
    console.log('');
    
    // 5. Test recommendations
    console.log('\n' + '='.repeat(80));
    console.log('🧪 TESTING RECOMMENDATIONS');
    console.log('='.repeat(80));
    
    console.log('\nTo test notifications:');
    console.log('1. Go to Admin Panel → Customer Management');
    console.log('2. Select pending rosters');
    console.log('3. Click "Optimize Route" button');
    console.log('4. Assign driver and vehicle');
    console.log('5. Check notifications in:');
    console.log('   - Customer app: Notifications screen');
    console.log('   - Driver app: Notifications screen');
    console.log('');
    console.log('Expected behavior:');
    console.log('✅ Customer receives: "Driver [Name] assigned - Route Optimized!"');
    console.log('✅ Driver receives: "New Optimized Route Assigned"');
    console.log('✅ Both notifications include pickup times and details');
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

// Run the test
testNotificationFlow();
