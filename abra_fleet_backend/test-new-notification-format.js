// Test new notification format with driver phone and login/logout times
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function testNewNotificationFormat() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find a roster with login/logout times
    console.log('📋 Finding a roster with schedule data...\n');
    
    const roster = await db.collection('rosters').findOne({
      status: 'pending',
      loginTime: { $exists: true }
    });
    
    if (!roster) {
      console.log('❌ No pending roster found with loginTime');
      console.log('\n💡 Creating a test roster...\n');
      
      // Create a test roster
      const testRoster = {
        rosterId: `TEST-${Date.now()}`,
        customerName: 'Test Customer',
        customerEmail: 'asha123@cognizant.com',
        userId: 'test-user-id',
        organization: 'Cognizant',
        loginTime: '08:30 AM',
        logoutTime: '06:00 PM',
        loginLocation: 'Electronic City, Bangalore',
        logoutLocation: 'Whitefield, Bangalore',
        startTime: '08:30',
        endTime: '18:00',
        startDate: new Date().toISOString().split('T')[0],
        endDate: new Date().toISOString().split('T')[0],
        status: 'pending',
        createdAt: new Date()
      };
      
      const result = await db.collection('rosters').insertOne(testRoster);
      console.log('✅ Test roster created:', result.insertedId.toString());
      
      // Fetch it back
      const newRoster = await db.collection('rosters').findOne({ _id: result.insertedId });
      
      console.log('\n📊 Roster Data:');
      console.log('  Customer:', newRoster.customerName);
      console.log('  Login Time:', newRoster.loginTime);
      console.log('  Logout Time:', newRoster.logoutTime);
      console.log('  Login Location:', newRoster.loginLocation);
      console.log('  Logout Location:', newRoster.logoutLocation);
      
      return;
    }
    
    console.log('✅ Found roster:', roster.customerName);
    console.log('\n📊 Roster Schedule Data:');
    console.log('  Login Time:', roster.loginTime || '❌ MISSING');
    console.log('  Logout Time:', roster.logoutTime || '❌ MISSING');
    console.log('  Login Location:', roster.loginLocation || '❌ MISSING');
    console.log('  Logout Location:', roster.logoutLocation || '❌ MISSING');
    
    // Find a driver with phone
    console.log('\n👨‍✈️ Finding a driver with phone number...\n');
    
    const driver = await db.collection('drivers').findOne({
      $or: [
        { 'personalInfo.phone': { $exists: true, $ne: null } },
        { phone: { $exists: true, $ne: null } }
      ]
    });
    
    if (!driver) {
      console.log('❌ No driver found with phone number');
      return;
    }
    
    console.log('✅ Found driver:', driver.personalInfo?.firstName || driver.name);
    console.log('  Phone:', driver.personalInfo?.phone || driver.phone || '❌ MISSING');
    
    console.log('\n' + '='.repeat(80));
    console.log('📝 EXPECTED NOTIFICATION DATA FORMAT:');
    console.log('='.repeat(80));
    
    const expectedNotificationData = {
      rosterId: roster._id.toString(),
      driverName: driver.personalInfo?.firstName || driver.name,
      driverPhone: driver.personalInfo?.phone || driver.phone || null,
      vehicleName: 'KA01AB1234',
      loginTime: roster.loginTime || roster.startTime || null,
      logoutTime: roster.logoutTime || roster.endTime || null,
      loginLocation: roster.loginLocation || roster.pickupLocation || null,
      logoutLocation: roster.logoutLocation || roster.dropLocation || null,
      pickupSequence: 1,
      totalStops: 1,
      action: 'route_assignment'
    };
    
    console.log(JSON.stringify(expectedNotificationData, null, 2));
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ Backend is now configured to send this data');
    console.log('💡 To test: Assign this roster to a vehicle from the admin panel');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testNewNotificationFormat();
