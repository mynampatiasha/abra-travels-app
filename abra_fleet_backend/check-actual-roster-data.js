// Check what data is actually in rosters
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function checkActualRosterData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find recent rosters
    console.log('📋 Checking recent rosters...\n');
    
    const rosters = await db.collection('rosters')
      .find({})
      .sort({ createdAt: -1 })
      .limit(3)
      .toArray();
    
    console.log(`Found ${rosters.length} rosters\n`);
    
    rosters.forEach((roster, index) => {
      console.log(`\n${'='.repeat(80)}`);
      console.log(`Roster ${index + 1}:`);
      console.log(`${'='.repeat(80)}`);
      console.log('ID:', roster._id.toString());
      console.log('Customer:', roster.customerName || roster.employeeDetails?.name);
      console.log('Status:', roster.status);
      console.log('\n📊 Schedule Fields:');
      console.log('  startTime:', roster.startTime || '❌ MISSING');
      console.log('  endTime:', roster.endTime || '❌ MISSING');
      console.log('  loginTime:', roster.loginTime || '❌ MISSING');
      console.log('  logoutTime:', roster.logoutTime || '❌ MISSING');
      console.log('  officeTime:', roster.officeTime || '❌ MISSING');
      
      console.log('\n📍 Location Fields:');
      console.log('  pickupLocation:', roster.pickupLocation || '❌ MISSING');
      console.log('  dropLocation:', roster.dropLocation || '❌ MISSING');
      console.log('  loginLocation:', roster.loginLocation || '❌ MISSING');
      console.log('  logoutLocation:', roster.logoutLocation || '❌ MISSING');
      console.log('  officeLocation:', roster.officeLocation || '❌ MISSING');
      
      console.log('\n🗺️  Locations Object:');
      if (roster.locations) {
        console.log(JSON.stringify(roster.locations, null, 2));
      } else {
        console.log('  ❌ No locations object');
      }
      
      console.log('\n👤 Customer Info:');
      console.log('  customerEmail:', roster.customerEmail || '❌ MISSING');
      console.log('  userId:', roster.userId || '❌ MISSING');
      
      if (roster.employeeDetails) {
        console.log('\n👤 Employee Details:');
        console.log(JSON.stringify(roster.employeeDetails, null, 2));
      }
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ Check complete');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkActualRosterData();
