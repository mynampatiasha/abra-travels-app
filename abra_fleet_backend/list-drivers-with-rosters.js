// Script to list all drivers with assigned rosters and their email addresses
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function listDriversWithRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    const rostersCollection = db.collection('rosters');
    const driversCollection = db.collection('drivers');
    
    // Get today's date range
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    console.log(`📅 Checking rosters for today: ${today.toISOString().split('T')[0]}\n`);
    
    // Find all rosters for today
    const todayRosters = await rostersCollection.find({
      startDate: { $lte: today },
      endDate: { $gte: today }
    }).toArray();
    
    console.log(`📋 Total rosters for today: ${todayRosters.length}\n`);
    
    // Group rosters by driver
    const driverRosterMap = {};
    
    for (const roster of todayRosters) {
      const driverId = roster.assignedDriver;
      if (driverId) {
        if (!driverRosterMap[driverId]) {
          driverRosterMap[driverId] = [];
        }
        driverRosterMap[driverId].push(roster);
      }
    }
    
    console.log(`👥 Drivers with rosters assigned: ${Object.keys(driverRosterMap).length}\n`);
    console.log('=' .repeat(80));
    
    // Get driver details for each driver with rosters
    for (const [driverId, rosters] of Object.entries(driverRosterMap)) {
      const driver = await driversCollection.findOne({ _id: driverId });
      
      if (driver) {
        console.log(`\n👤 Driver: ${driver.name || 'N/A'}`);
        console.log(`   📧 Email: ${driver.email || 'N/A'}`);
        console.log(`   🆔 Driver ID: ${driver.driverId || 'N/A'}`);
        console.log(`   🔑 MongoDB _id: ${driverId}`);
        console.log(`   🔥 Firebase UID: ${driver.uid || 'NOT SET'}`);
        console.log(`   📊 Status: ${driver.status || 'N/A'}`);
        console.log(`   📦 Rosters assigned: ${rosters.length}`);
        
        // Show roster details
        console.log(`   📍 Customers:`);
        for (let i = 0; i < rosters.length; i++) {
          const roster = rosters[i];
          console.log(`      ${i + 1}. ${roster.customerName || 'Unknown'} (${roster.userId || 'No userId'})`);
        }
      } else {
        console.log(`\n⚠️  Driver with MongoDB _id ${driverId} not found in drivers collection`);
        console.log(`   📦 Rosters assigned: ${rosters.length}`);
      }
      
      console.log('-'.repeat(80));
    }
    
    // Also show drivers WITHOUT rosters
    console.log('\n\n📋 DRIVERS WITHOUT ROSTERS FOR TODAY:');
    console.log('=' .repeat(80));
    
    const allDrivers = await driversCollection.find({}).toArray();
    const driversWithoutRosters = allDrivers.filter(driver => 
      !driverRosterMap[driver._id.toString()]
    );
    
    if (driversWithoutRosters.length === 0) {
      console.log('✅ All drivers have rosters assigned!');
    } else {
      for (const driver of driversWithoutRosters) {
        console.log(`\n👤 Driver: ${driver.name || 'N/A'}`);
        console.log(`   📧 Email: ${driver.email || 'N/A'}`);
        console.log(`   🆔 Driver ID: ${driver.driverId || 'N/A'}`);
        console.log(`   🔥 Firebase UID: ${driver.uid || 'NOT SET'}`);
        console.log(`   📊 Status: ${driver.status || 'N/A'}`);
        console.log(`   ⚠️  NO ROSTERS ASSIGNED`);
        console.log('-'.repeat(80));
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

listDriversWithRosters();
